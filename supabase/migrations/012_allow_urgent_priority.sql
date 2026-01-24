-- ============================================
-- AUDAZ PRO - TICKET SYSTEM MIGRATIONS
-- Migration 012: Allow urgent priority values
-- ============================================

-- Allow urgent priority in the tickets priority check constraint
ALTER TABLE public.tickets
  DROP CONSTRAINT IF EXISTS tickets_priority_check;

ALTER TABLE public.tickets
  ADD CONSTRAINT tickets_priority_check CHECK (priority IN ('baixa', 'media', 'alta', 'urgente'));

-- Update create_ticket function so existing databases accept the new value
CREATE OR REPLACE FUNCTION public.create_ticket(
    p_type TEXT,
    p_title TEXT,
    p_description TEXT,
    p_priority TEXT,
    p_category TEXT DEFAULT NULL,
    p_attachment_url TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_user_profile RECORD;
    v_ticket_id UUID;
BEGIN
    -- Get current user's profile
    SELECT * INTO v_user_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Profile not found');
    END IF;

    -- Only clients can create tickets
    IF v_user_profile.role NOT IN ('client_admin', 'client_user') THEN
        RETURN json_build_object('success', false, 'error', 'Only clients can create tickets');
    END IF;

    -- Validate type
    IF p_type NOT IN ('alteracao', 'suporte') THEN
        RETURN json_build_object('success', false, 'error', 'Invalid type');
    END IF;

    -- Validate priority
    IF p_priority NOT IN ('baixa', 'media', 'alta', 'urgente') THEN
        RETURN json_build_object('success', false, 'error', 'Invalid priority');
    END IF;

    -- Create the ticket
    INSERT INTO public.tickets (
        org_id, type, title, description, priority, category, attachment_url, created_by
    ) VALUES (
        v_user_profile.org_id, p_type, p_title, p_description, p_priority, p_category, p_attachment_url, v_user_profile.id
    )
    RETURNING id INTO v_ticket_id;

    -- Create the "created" event
    INSERT INTO public.ticket_events (ticket_id, org_id, actor_id, event_type, payload)
    VALUES (
        v_ticket_id,
        v_user_profile.org_id,
        v_user_profile.id,
        'created',
        json_build_object('type', p_type, 'priority', p_priority)
    );

    -- AUTO-ADD: Creator as collaborator
    INSERT INTO public.ticket_collaborators (ticket_id, user_id, role, added_by)
    VALUES (v_ticket_id, v_user_profile.id, 'creator', v_user_profile.id);

    RETURN json_build_object(
        'success', true,
        'ticket_id', v_ticket_id
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'error', SQLERRM
        );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
