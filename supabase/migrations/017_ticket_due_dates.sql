-- ============================================
-- AUDAZ PRO - TICKET SYSTEM MIGRATIONS
-- Migration 017: Manual Ticket Due Dates
-- ============================================

ALTER TABLE public.tickets
ADD COLUMN IF NOT EXISTS due_date DATE;

COMMENT ON COLUMN public.tickets.due_date IS 'Manual due date set by support; NULL uses the priority-based default deadline';

-- Allow audit events for manual due date changes.
ALTER TABLE public.ticket_events
DROP CONSTRAINT IF EXISTS ticket_events_event_type_check;

ALTER TABLE public.ticket_events
ADD CONSTRAINT ticket_events_event_type_check
CHECK (event_type IN (
    'created',
    'status_changed',
    'assigned',
    'commented',
    'priority_changed',
    'request_units_changed',
    'due_date_changed'
));

CREATE OR REPLACE FUNCTION public.update_ticket_due_date(
    p_ticket_id UUID,
    p_due_date DATE,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_profile RECORD;
    v_ticket RECORD;
BEGIN
    SELECT * INTO v_user_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT FOUND OR v_user_profile.role NOT IN ('support_agent', 'support_admin') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Only support can update due dates');
    END IF;

    SELECT * INTO v_ticket
    FROM public.tickets
    WHERE id = p_ticket_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Ticket not found');
    END IF;

    IF v_ticket.due_date IS NOT DISTINCT FROM p_due_date THEN
        RETURN jsonb_build_object(
            'success', true,
            'ticket_id', p_ticket_id,
            'old_due_date', v_ticket.due_date,
            'new_due_date', p_due_date,
            'changed', false
        );
    END IF;

    UPDATE public.tickets
    SET due_date = p_due_date
    WHERE id = p_ticket_id;

    INSERT INTO public.ticket_events (ticket_id, org_id, actor_id, event_type, payload)
    VALUES (
        p_ticket_id,
        v_ticket.org_id,
        v_user_profile.id,
        'due_date_changed',
        jsonb_build_object(
            'from', v_ticket.due_date,
            'to', p_due_date,
            'reason', NULLIF(trim(COALESCE(p_reason, '')), '')
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'ticket_id', p_ticket_id,
        'old_due_date', v_ticket.due_date,
        'new_due_date', p_due_date,
        'changed', true
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_ticket_due_date(UUID, DATE, TEXT) TO authenticated;
