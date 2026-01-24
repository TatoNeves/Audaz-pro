-- ============================================
-- AUDAZ PRO - TICKET COLLABORATORS
-- Migration 008: Collaborators System
--
-- Execute this in Supabase Dashboard > SQL Editor
-- ============================================

-- ============================================
-- TABLE: ticket_collaborators
-- Users who should be notified about ticket updates
-- ============================================
CREATE TABLE IF NOT EXISTS public.ticket_collaborators (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID REFERENCES public.tickets(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('creator', 'assignee', 'mentioned', 'manual')),
    added_by UUID REFERENCES public.profiles(id),
    added_at TIMESTAMPTZ DEFAULT NOW(),

    -- Prevent duplicate user-ticket combinations
    UNIQUE(ticket_id, user_id)
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_ticket_collaborators_ticket_id ON public.ticket_collaborators(ticket_id);
CREATE INDEX IF NOT EXISTS idx_ticket_collaborators_user_id ON public.ticket_collaborators(user_id);

COMMENT ON TABLE public.ticket_collaborators IS 'Users who should be notified about ticket updates';
COMMENT ON COLUMN public.ticket_collaborators.role IS 'How the user became a collaborator: creator, assignee, mentioned, or manual';

-- ============================================
-- TABLE: notification_queue
-- Queue for email notifications to be processed
-- ============================================
CREATE TABLE IF NOT EXISTS public.notification_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID REFERENCES public.tickets(id) ON DELETE CASCADE NOT NULL,
    recipient_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    notification_type TEXT NOT NULL CHECK (notification_type IN ('mention', 'status_change', 'new_comment', 'assigned')),
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    status TEXT NOT NULL CHECK (status IN ('pending', 'sent', 'failed')) DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    sent_at TIMESTAMPTZ,
    error_message TEXT
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_notification_queue_status ON public.notification_queue(status) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_notification_queue_created_at ON public.notification_queue(created_at);

COMMENT ON TABLE public.notification_queue IS 'Queue for email notifications to be processed';

-- ============================================
-- ENABLE RLS
-- ============================================
ALTER TABLE public.ticket_collaborators ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_queue ENABLE ROW LEVEL SECURITY;

-- ============================================
-- RLS POLICIES: ticket_collaborators
-- ============================================

-- Clients can view collaborators for their org's tickets
DROP POLICY IF EXISTS "Clients can view org ticket collaborators" ON public.ticket_collaborators;
CREATE POLICY "Clients can view org ticket collaborators"
    ON public.ticket_collaborators FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.tickets t
            WHERE t.id = ticket_id
            AND t.org_id = public.get_my_org_id()
        )
        AND public.get_my_role() IN ('client_admin', 'client_user')
    );

-- Support can view all collaborators
DROP POLICY IF EXISTS "Support can view all collaborators" ON public.ticket_collaborators;
CREATE POLICY "Support can view all collaborators"
    ON public.ticket_collaborators FOR SELECT
    USING (public.is_support());

-- Clients can add collaborators to their org's tickets
DROP POLICY IF EXISTS "Clients can add collaborators" ON public.ticket_collaborators;
CREATE POLICY "Clients can add collaborators"
    ON public.ticket_collaborators FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.tickets t
            WHERE t.id = ticket_id
            AND t.org_id = public.get_my_org_id()
        )
        AND public.get_my_role() IN ('client_admin', 'client_user')
    );

-- Support can add collaborators
DROP POLICY IF EXISTS "Support can add collaborators" ON public.ticket_collaborators;
CREATE POLICY "Support can add collaborators"
    ON public.ticket_collaborators FOR INSERT
    WITH CHECK (public.is_support());

-- Clients can remove collaborators (only manual/mentioned ones)
DROP POLICY IF EXISTS "Clients can remove collaborators" ON public.ticket_collaborators;
CREATE POLICY "Clients can remove collaborators"
    ON public.ticket_collaborators FOR DELETE
    USING (
        role IN ('manual', 'mentioned')
        AND EXISTS (
            SELECT 1 FROM public.tickets t
            WHERE t.id = ticket_id
            AND t.org_id = public.get_my_org_id()
        )
        AND public.get_my_role() IN ('client_admin', 'client_user')
    );

-- Support can remove any collaborators (except creator)
DROP POLICY IF EXISTS "Support can remove collaborators" ON public.ticket_collaborators;
CREATE POLICY "Support can remove collaborators"
    ON public.ticket_collaborators FOR DELETE
    USING (
        role != 'creator'
        AND public.is_support()
    );

-- ============================================
-- RLS POLICIES: notification_queue
-- ============================================

-- Support admin can view notifications
DROP POLICY IF EXISTS "Support admin can view notifications" ON public.notification_queue;
CREATE POLICY "Support admin can view notifications"
    ON public.notification_queue FOR SELECT
    USING (public.get_my_role() = 'support_admin');

-- ============================================
-- FUNCTION: Get ticket collaborators
-- ============================================
CREATE OR REPLACE FUNCTION public.get_ticket_collaborators(p_ticket_id UUID)
RETURNS JSON AS $$
DECLARE
    v_user_profile RECORD;
    v_ticket RECORD;
    v_collaborators JSON;
BEGIN
    -- Get current user's profile
    SELECT * INTO v_user_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Profile not found');
    END IF;

    -- Get the ticket
    SELECT * INTO v_ticket
    FROM public.tickets
    WHERE id = p_ticket_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Ticket not found');
    END IF;

    -- Check permissions for clients
    IF v_user_profile.role IN ('client_admin', 'client_user') THEN
        IF v_ticket.org_id != v_user_profile.org_id THEN
            RETURN json_build_object('success', false, 'error', 'Access denied');
        END IF;
    END IF;

    -- Get collaborators with profile info
    SELECT json_agg(row_to_json(c)) INTO v_collaborators
    FROM (
        SELECT
            tc.id,
            tc.user_id,
            tc.role,
            tc.added_at,
            p.full_name,
            p.avatar_url,
            p.role as user_role,
            u.email
        FROM public.ticket_collaborators tc
        JOIN public.profiles p ON p.id = tc.user_id
        LEFT JOIN auth.users u ON u.id = p.id
        WHERE tc.ticket_id = p_ticket_id
        ORDER BY
            CASE tc.role
                WHEN 'creator' THEN 1
                WHEN 'assignee' THEN 2
                WHEN 'mentioned' THEN 3
                ELSE 4
            END,
            tc.added_at
    ) c;

    RETURN json_build_object(
        'success', true,
        'collaborators', COALESCE(v_collaborators, '[]'::json)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- FUNCTION: Add collaborator
-- ============================================
CREATE OR REPLACE FUNCTION public.add_ticket_collaborator(
    p_ticket_id UUID,
    p_user_id UUID,
    p_role TEXT DEFAULT 'manual'
)
RETURNS JSON AS $$
DECLARE
    v_user_profile RECORD;
    v_ticket RECORD;
    v_collaborator_id UUID;
BEGIN
    -- Get current user's profile
    SELECT * INTO v_user_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Profile not found');
    END IF;

    -- Get the ticket
    SELECT * INTO v_ticket
    FROM public.tickets
    WHERE id = p_ticket_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Ticket not found');
    END IF;

    -- Check permissions for clients
    IF v_user_profile.role IN ('client_admin', 'client_user') THEN
        IF v_ticket.org_id != v_user_profile.org_id THEN
            RETURN json_build_object('success', false, 'error', 'Access denied');
        END IF;

        -- Clients can only add users from their own org
        IF NOT EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = p_user_id AND org_id = v_ticket.org_id
        ) THEN
            RETURN json_build_object('success', false, 'error', 'User must be from the same organization');
        END IF;
    END IF;

    -- Upsert the collaborator (don't downgrade creator/assignee roles)
    INSERT INTO public.ticket_collaborators (ticket_id, user_id, role, added_by)
    VALUES (p_ticket_id, p_user_id, p_role, v_user_profile.id)
    ON CONFLICT (ticket_id, user_id) DO UPDATE SET
        role = CASE
            WHEN ticket_collaborators.role IN ('creator', 'assignee') THEN ticket_collaborators.role
            ELSE EXCLUDED.role
        END
    RETURNING id INTO v_collaborator_id;

    RETURN json_build_object(
        'success', true,
        'collaborator_id', v_collaborator_id
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'error', SQLERRM
        );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- FUNCTION: Remove collaborator
-- ============================================
CREATE OR REPLACE FUNCTION public.remove_ticket_collaborator(
    p_ticket_id UUID,
    p_user_id UUID
)
RETURNS JSON AS $$
DECLARE
    v_user_profile RECORD;
    v_ticket RECORD;
    v_collaborator RECORD;
BEGIN
    -- Get current user's profile
    SELECT * INTO v_user_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Profile not found');
    END IF;

    -- Get the collaborator record
    SELECT * INTO v_collaborator
    FROM public.ticket_collaborators
    WHERE ticket_id = p_ticket_id AND user_id = p_user_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Collaborator not found');
    END IF;

    -- Cannot remove creator
    IF v_collaborator.role = 'creator' THEN
        RETURN json_build_object('success', false, 'error', 'Cannot remove ticket creator');
    END IF;

    -- Get the ticket for permission check
    SELECT * INTO v_ticket
    FROM public.tickets
    WHERE id = p_ticket_id;

    -- Check permissions for clients
    IF v_user_profile.role IN ('client_admin', 'client_user') THEN
        IF v_ticket.org_id != v_user_profile.org_id THEN
            RETURN json_build_object('success', false, 'error', 'Access denied');
        END IF;
        -- Clients cannot remove assignee
        IF v_collaborator.role = 'assignee' THEN
            RETURN json_build_object('success', false, 'error', 'Cannot remove assignee');
        END IF;
    END IF;

    -- Delete the collaborator
    DELETE FROM public.ticket_collaborators
    WHERE ticket_id = p_ticket_id AND user_id = p_user_id;

    RETURN json_build_object('success', true);
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'error', SQLERRM
        );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- FUNCTION: Queue notification (internal use)
-- ============================================
CREATE OR REPLACE FUNCTION public.queue_notification(
    p_ticket_id UUID,
    p_recipient_id UUID,
    p_type TEXT,
    p_payload JSONB
)
RETURNS VOID AS $$
BEGIN
    -- Don't notify self
    IF p_recipient_id = auth.uid() THEN
        RETURN;
    END IF;

    INSERT INTO public.notification_queue (ticket_id, recipient_id, notification_type, payload)
    VALUES (p_ticket_id, p_recipient_id, p_type, p_payload)
    ON CONFLICT DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- UPDATE EXISTING FUNCTIONS
-- ============================================

-- Drop existing functions first to avoid return type conflicts
DROP FUNCTION IF EXISTS public.create_ticket(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.assign_ticket(UUID, UUID);
DROP FUNCTION IF EXISTS public.add_ticket_comment(UUID, TEXT);
DROP FUNCTION IF EXISTS public.update_ticket_status(UUID, TEXT);

-- Update create_ticket to auto-add creator as collaborator
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

-- Update assign_ticket to auto-add assignee as collaborator
CREATE OR REPLACE FUNCTION public.assign_ticket(
    p_ticket_id UUID,
    p_assignee_id UUID
)
RETURNS JSON AS $$
DECLARE
    v_user_profile RECORD;
    v_assignee_profile RECORD;
    v_ticket RECORD;
    v_old_assignee UUID;
BEGIN
    -- Get current user's profile
    SELECT * INTO v_user_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Profile not found');
    END IF;

    -- Only support can assign tickets
    IF v_user_profile.role NOT IN ('support_agent', 'support_admin') THEN
        RETURN json_build_object('success', false, 'error', 'Only support can assign tickets');
    END IF;

    -- Get the ticket
    SELECT * INTO v_ticket
    FROM public.tickets
    WHERE id = p_ticket_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Ticket not found');
    END IF;

    -- Get the assignee's profile
    SELECT * INTO v_assignee_profile
    FROM public.profiles
    WHERE id = p_assignee_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'User not found');
    END IF;

    v_old_assignee := v_ticket.assigned_to;

    -- Update the ticket
    UPDATE public.tickets
    SET assigned_to = p_assignee_id
    WHERE id = p_ticket_id;

    -- Create assignment event
    INSERT INTO public.ticket_events (ticket_id, org_id, actor_id, event_type, payload)
    VALUES (
        p_ticket_id,
        v_ticket.org_id,
        v_user_profile.id,
        'assigned',
        json_build_object('assigned_to', p_assignee_id, 'assignee_name', v_assignee_profile.full_name)
    );

    -- AUTO-ADD: New assignee as collaborator
    INSERT INTO public.ticket_collaborators (ticket_id, user_id, role, added_by)
    VALUES (p_ticket_id, p_assignee_id, 'assignee', v_user_profile.id)
    ON CONFLICT (ticket_id, user_id) DO UPDATE SET role = 'assignee';

    -- If there was an old assignee, downgrade their role to 'manual'
    IF v_old_assignee IS NOT NULL AND v_old_assignee != p_assignee_id THEN
        UPDATE public.ticket_collaborators
        SET role = 'manual'
        WHERE ticket_id = p_ticket_id
        AND user_id = v_old_assignee
        AND role = 'assignee';
    END IF;

    -- QUEUE NOTIFICATION: Notify new assignee
    PERFORM public.queue_notification(
        p_ticket_id,
        p_assignee_id,
        'assigned',
        json_build_object(
            'ticket_title', v_ticket.title,
            'assigned_by', v_user_profile.full_name
        )::jsonb
    );

    RETURN json_build_object('success', true);
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'error', SQLERRM
        );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update add_ticket_comment to parse mentions and notify collaborators
CREATE OR REPLACE FUNCTION public.add_ticket_comment(
    p_ticket_id UUID,
    p_body TEXT
)
RETURNS JSON AS $$
DECLARE
    v_user_profile RECORD;
    v_ticket RECORD;
    v_comment_id UUID;
    v_mentioned_name TEXT;
    v_mentioned_user RECORD;
    v_collaborator RECORD;
BEGIN
    -- Get current user's profile
    SELECT * INTO v_user_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Profile not found');
    END IF;

    -- Get the ticket
    SELECT * INTO v_ticket
    FROM public.tickets
    WHERE id = p_ticket_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Ticket not found');
    END IF;

    -- Check permissions for clients
    IF v_user_profile.role IN ('client_admin', 'client_user') THEN
        IF v_ticket.org_id != v_user_profile.org_id THEN
            RETURN json_build_object('success', false, 'error', 'Access denied');
        END IF;
    END IF;

    -- Create the comment
    INSERT INTO public.ticket_comments (ticket_id, org_id, author_id, body)
    VALUES (p_ticket_id, v_ticket.org_id, v_user_profile.id, p_body)
    RETURNING id INTO v_comment_id;

    -- Create comment event
    INSERT INTO public.ticket_events (ticket_id, org_id, actor_id, event_type, payload)
    VALUES (
        p_ticket_id,
        v_ticket.org_id,
        v_user_profile.id,
        'commented',
        json_build_object('comment_id', v_comment_id)
    );

    -- PARSE MENTIONS: Find @Name patterns and add as collaborators
    -- Pattern matches @FirstName LastName (two words after @)
    FOR v_mentioned_name IN
        SELECT DISTINCT trim(match[1])
        FROM regexp_matches(p_body, '@([A-Za-zÀ-ÿ]+ [A-Za-zÀ-ÿ]+)', 'g') AS match
    LOOP
        -- Find user by name in the ticket's org
        SELECT * INTO v_mentioned_user
        FROM public.profiles
        WHERE full_name ILIKE v_mentioned_name
        AND org_id = v_ticket.org_id
        LIMIT 1;

        IF FOUND THEN
            -- Add as collaborator (if not already)
            INSERT INTO public.ticket_collaborators (ticket_id, user_id, role, added_by)
            VALUES (p_ticket_id, v_mentioned_user.id, 'mentioned', v_user_profile.id)
            ON CONFLICT (ticket_id, user_id) DO NOTHING;

            -- Queue mention notification
            PERFORM public.queue_notification(
                p_ticket_id,
                v_mentioned_user.id,
                'mention',
                json_build_object(
                    'ticket_title', v_ticket.title,
                    'mentioned_by', v_user_profile.full_name,
                    'comment_preview', left(p_body, 200)
                )::jsonb
            );
        END IF;
    END LOOP;

    -- QUEUE NOTIFICATIONS: Notify all collaborators about new comment (except author and mentioned users)
    FOR v_collaborator IN
        SELECT tc.user_id
        FROM public.ticket_collaborators tc
        WHERE tc.ticket_id = p_ticket_id
        AND tc.user_id != v_user_profile.id
    LOOP
        PERFORM public.queue_notification(
            p_ticket_id,
            v_collaborator.user_id,
            'new_comment',
            json_build_object(
                'ticket_title', v_ticket.title,
                'comment_by', v_user_profile.full_name,
                'comment_preview', left(p_body, 200)
            )::jsonb
        );
    END LOOP;

    RETURN json_build_object(
        'success', true,
        'comment_id', v_comment_id
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'error', SQLERRM
        );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update update_ticket_status to notify collaborators
CREATE OR REPLACE FUNCTION public.update_ticket_status(
    p_ticket_id UUID,
    p_status TEXT
)
RETURNS JSON AS $$
DECLARE
    v_user_profile RECORD;
    v_ticket RECORD;
    v_old_status TEXT;
    v_collaborator RECORD;
BEGIN
    -- Get current user's profile
    SELECT * INTO v_user_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Profile not found');
    END IF;

    -- Validate status
    IF p_status NOT IN ('open', 'in_progress', 'done') THEN
        RETURN json_build_object('success', false, 'error', 'Invalid status');
    END IF;

    -- Get the ticket
    SELECT * INTO v_ticket
    FROM public.tickets
    WHERE id = p_ticket_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Ticket not found');
    END IF;

    -- Check permissions
    IF v_user_profile.role IN ('client_admin', 'client_user') THEN
        IF v_ticket.org_id != v_user_profile.org_id THEN
            RETURN json_build_object('success', false, 'error', 'Access denied');
        END IF;
    END IF;

    v_old_status := v_ticket.status;

    -- Update the ticket
    UPDATE public.tickets
    SET status = p_status
    WHERE id = p_ticket_id;

    -- Create status change event
    INSERT INTO public.ticket_events (ticket_id, org_id, actor_id, event_type, payload)
    VALUES (
        p_ticket_id,
        v_ticket.org_id,
        v_user_profile.id,
        'status_changed',
        json_build_object('from', v_old_status, 'to', p_status)
    );

    -- QUEUE NOTIFICATIONS: Notify all collaborators about status change
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
        RETURN json_build_object(
            'success', false,
            'error', SQLERRM
        );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- GRANT PERMISSIONS
-- ============================================
GRANT EXECUTE ON FUNCTION public.get_ticket_collaborators TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_ticket_collaborator TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_ticket_collaborator TO authenticated;
GRANT EXECUTE ON FUNCTION public.queue_notification TO authenticated;

-- ============================================
-- BACKFILL: Add collaborators for existing tickets
-- ============================================
DO $$
DECLARE
    v_ticket RECORD;
BEGIN
    FOR v_ticket IN SELECT id, created_by, assigned_to FROM public.tickets
    LOOP
        -- Add creator as collaborator
        INSERT INTO public.ticket_collaborators (ticket_id, user_id, role, added_by)
        VALUES (v_ticket.id, v_ticket.created_by, 'creator', v_ticket.created_by)
        ON CONFLICT (ticket_id, user_id) DO NOTHING;

        -- Add assignee as collaborator if exists
        IF v_ticket.assigned_to IS NOT NULL THEN
            INSERT INTO public.ticket_collaborators (ticket_id, user_id, role, added_by)
            VALUES (v_ticket.id, v_ticket.assigned_to, 'assignee', v_ticket.assigned_to)
            ON CONFLICT (ticket_id, user_id) DO UPDATE SET role = 'assignee';
        END IF;
    END LOOP;
END;
$$;

-- Verify tables were created
SELECT 'ticket_collaborators' as table_name, COUNT(*) as count FROM public.ticket_collaborators
UNION ALL
SELECT 'notification_queue', COUNT(*) FROM public.notification_queue;
