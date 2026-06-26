-- ============================================
-- Migration 021: Add Client Review Ticket Status
-- ============================================

DO $$
DECLARE
    v_constraint_name TEXT;
BEGIN
    SELECT conname INTO v_constraint_name
    FROM pg_constraint
    WHERE conrelid = 'public.tickets'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) LIKE '%status%'
      AND pg_get_constraintdef(oid) LIKE '%open%'
      AND pg_get_constraintdef(oid) LIKE '%in_progress%'
      AND pg_get_constraintdef(oid) LIKE '%done%'
    LIMIT 1;

    IF v_constraint_name IS NOT NULL THEN
        EXECUTE format('ALTER TABLE public.tickets DROP CONSTRAINT %I', v_constraint_name);
    END IF;
END $$;

ALTER TABLE public.tickets
ADD CONSTRAINT tickets_status_check
CHECK (status IN ('open', 'in_progress', 'client_review', 'done', 'cancelled'));

CREATE OR REPLACE FUNCTION public.update_ticket_status(
    p_ticket_id UUID,
    p_status TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_profile RECORD;
    v_ticket RECORD;
    v_old_status TEXT;
    v_collaborator RECORD;
BEGIN
    SELECT * INTO v_user_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Profile not found');
    END IF;

    IF p_status NOT IN ('open', 'in_progress', 'client_review', 'done', 'cancelled') THEN
        RETURN json_build_object('success', false, 'error', 'Invalid status');
    END IF;

    SELECT * INTO v_ticket
    FROM public.tickets
    WHERE id = p_ticket_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Ticket not found');
    END IF;

    IF v_user_profile.role IN ('client_admin', 'client_user') THEN
        IF v_ticket.org_id != v_user_profile.org_id THEN
            RETURN json_build_object('success', false, 'error', 'Access denied');
        END IF;
    ELSIF NOT public.can_support_access_ticket(p_ticket_id) THEN
        RETURN json_build_object('success', false, 'error', 'Access denied');
    END IF;

    v_old_status := v_ticket.status;

    UPDATE public.tickets
    SET status = p_status
    WHERE id = p_ticket_id;

    INSERT INTO public.ticket_events (ticket_id, org_id, actor_id, event_type, payload)
    VALUES (p_ticket_id, v_ticket.org_id, v_user_profile.id, 'status_changed', json_build_object('from', v_old_status, 'to', p_status));

    FOR v_collaborator IN
        SELECT tc.user_id
        FROM public.ticket_collaborators tc
        WHERE tc.ticket_id = p_ticket_id
        AND tc.user_id != v_user_profile.id
    LOOP
        PERFORM public.queue_notification(
            p_ticket_id,
            v_collaborator.user_id,
            'status_change',
            json_build_object(
                'ticket_title', v_ticket.title,
                'changed_by', v_user_profile.full_name,
                'old_status', v_old_status,
                'new_status', p_status
            )::jsonb
        );
    END LOOP;

    RETURN json_build_object('success', true);
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;
