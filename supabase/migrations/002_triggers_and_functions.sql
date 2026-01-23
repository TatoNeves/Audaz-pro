-- ============================================
-- AUDAZ PRO - TICKET SYSTEM MIGRATIONS
-- Migration 002: Triggers and Functions
-- ============================================

-- ============================================
-- HELPER FUNCTION: Update updated_at timestamp
-- ============================================
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- HELPER FUNCTION: Update last_activity_at on tickets
-- ============================================
CREATE OR REPLACE FUNCTION public.update_ticket_last_activity()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.tickets
    SET last_activity_at = NOW()
    WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- TRIGGERS: updated_at
-- ============================================

-- Profiles updated_at trigger
DROP TRIGGER IF EXISTS on_profiles_updated ON public.profiles;
CREATE TRIGGER on_profiles_updated
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();

-- Tickets updated_at trigger
DROP TRIGGER IF EXISTS on_tickets_updated ON public.tickets;
CREATE TRIGGER on_tickets_updated
    BEFORE UPDATE ON public.tickets
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();

-- ============================================
-- TRIGGERS: last_activity_at on tickets
-- ============================================

-- When a comment is added
DROP TRIGGER IF EXISTS on_comment_update_activity ON public.ticket_comments;
CREATE TRIGGER on_comment_update_activity
    AFTER INSERT ON public.ticket_comments
    FOR EACH ROW
    EXECUTE FUNCTION public.update_ticket_last_activity();

-- When an event is added
DROP TRIGGER IF EXISTS on_event_update_activity ON public.ticket_events;
CREATE TRIGGER on_event_update_activity
    AFTER INSERT ON public.ticket_events
    FOR EACH ROW
    EXECUTE FUNCTION public.update_ticket_last_activity();

-- ============================================
-- RPC FUNCTION: Create Organization on Signup
-- Creates org + profile atomically
-- ============================================
CREATE OR REPLACE FUNCTION public.create_organization_on_signup(
    p_user_id UUID,
    p_org_name TEXT,
    p_full_name TEXT
)
RETURNS JSON AS $$
DECLARE
    v_org_id UUID;
    v_profile_id UUID;
BEGIN
    -- Create the organization
    INSERT INTO public.organizations (name)
    VALUES (p_org_name)
    RETURNING id INTO v_org_id;

    -- Create the profile with client_admin role
    INSERT INTO public.profiles (id, org_id, role, full_name)
    VALUES (p_user_id, v_org_id, 'client_admin', p_full_name)
    RETURNING id INTO v_profile_id;

    RETURN json_build_object(
        'success', true,
        'org_id', v_org_id,
        'profile_id', v_profile_id
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
-- RPC FUNCTION: Create Support User
-- For creating support team members (admin only)
-- ============================================
CREATE OR REPLACE FUNCTION public.create_support_user(
    p_user_id UUID,
    p_full_name TEXT,
    p_role TEXT DEFAULT 'support_agent'
)
RETURNS JSON AS $$
BEGIN
    -- Validate role
    IF p_role NOT IN ('support_agent', 'support_admin') THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Invalid role. Must be support_agent or support_admin'
        );
    END IF;

    -- Create the profile without org (support doesn't belong to client orgs)
    INSERT INTO public.profiles (id, org_id, role, full_name)
    VALUES (p_user_id, NULL, p_role, p_full_name);

    RETURN json_build_object(
        'success', true,
        'profile_id', p_user_id
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
-- RPC FUNCTION: Accept Invitation
-- Validates token, expiration, org limit
-- ============================================
CREATE OR REPLACE FUNCTION public.accept_invitation(
    p_token TEXT,
    p_user_id UUID,
    p_full_name TEXT
)
RETURNS JSON AS $$
DECLARE
    v_invitation RECORD;
    v_org_member_count INTEGER;
    v_max_members INTEGER := 4;
BEGIN
    -- Find the invitation
    SELECT * INTO v_invitation
    FROM public.invitations
    WHERE token = p_token
    AND accepted_at IS NULL;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Invitation not found or already used'
        );
    END IF;

    -- Check if expired
    IF v_invitation.expires_at < NOW() THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Invitation expired'
        );
    END IF;

    -- Count existing members in the organization
    SELECT COUNT(*) INTO v_org_member_count
    FROM public.profiles
    WHERE org_id = v_invitation.org_id;

    -- Check if org has reached member limit
    IF v_org_member_count >= v_max_members THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Member limit reached (maximum 4 users per organization)'
        );
    END IF;

    -- Create the profile
    INSERT INTO public.profiles (id, org_id, role, full_name)
    VALUES (p_user_id, v_invitation.org_id, v_invitation.role, p_full_name);

    -- Mark invitation as accepted
    UPDATE public.invitations
    SET accepted_at = NOW()
    WHERE id = v_invitation.id;

    RETURN json_build_object(
        'success', true,
        'org_id', v_invitation.org_id,
        'role', v_invitation.role
    );
    EXCEPTION
        WHEN unique_violation THEN
            RETURN json_build_object(
                'success', false,
                'error', 'User already has a profile'
            );
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'error', SQLERRM
        );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- RPC FUNCTION: Create Invitation
-- With org member limit validation
-- ============================================
CREATE OR REPLACE FUNCTION public.create_invitation(
    p_email TEXT,
    p_role TEXT DEFAULT 'client_user'
)
RETURNS JSON AS $$
DECLARE
    v_user_profile RECORD;
    v_org_member_count INTEGER;
    v_pending_invites INTEGER;
    v_max_members INTEGER := 4;
    v_token TEXT;
    v_invitation_id UUID;
BEGIN
    -- Get the current user's profile
    SELECT * INTO v_user_profile
    FROM public.profiles
    WHERE id = auth.uid();


    -- Count existing members
    SELECT COUNT(*) INTO v_org_member_count
    FROM public.profiles
    WHERE org_id = v_user_profile.org_id;

    -- Count pending (non-expired, non-accepted) invitations
    SELECT COUNT(*) INTO v_pending_invites
    FROM public.invitations
    WHERE org_id = v_user_profile.org_id
    AND accepted_at IS NULL
    AND expires_at > NOW();

    -- Check if limit would be exceeded
    IF (v_org_member_count + v_pending_invites) >= v_max_members THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Member limit reached (maximum 4 users per organization)'
        );
    END IF;

    -- Check for existing pending invitation to same email
    IF EXISTS (
        SELECT 1 FROM public.invitations
        WHERE org_id = v_user_profile.org_id
        AND email = p_email
        AND accepted_at IS NULL
        AND expires_at > NOW()
    ) THEN
        RETURN json_build_object(
            'success', false,
            'error', 'A pending invitation already exists for this email'
        );
    END IF;

    -- Generate secure token
    v_token := encode(gen_random_bytes(32), 'hex');

    -- Create the invitation (expires in 7 days)
    INSERT INTO public.invitations (org_id, email, token, role, expires_at, created_by)
    VALUES (
        v_user_profile.org_id,
        p_email,
        v_token,
        p_role,
        NOW() + INTERVAL '7 days',
        v_user_profile.id
    )
    RETURNING id INTO v_invitation_id;

    RETURN json_build_object(
        'success', true,
        'invitation_id', v_invitation_id,
        'token', v_token,
        'expires_at', NOW() + INTERVAL '7 days'
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
-- RPC FUNCTION: Get Invitation by Token (public)
-- ============================================
CREATE OR REPLACE FUNCTION public.get_invitation_by_token(p_token TEXT)
RETURNS JSON AS $$
DECLARE
    v_invitation RECORD;
    v_org RECORD;
BEGIN
    SELECT i.*, o.name as org_name
    INTO v_invitation
    FROM public.invitations i
    JOIN public.organizations o ON o.id = i.org_id
    WHERE i.token = p_token;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Invitation not found'
        );
    END IF;

    IF v_invitation.accepted_at IS NOT NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Invitation already used'
        );
    END IF;

    IF v_invitation.expires_at < NOW() THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Invitation expired'
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'email', v_invitation.email,
        'org_name', v_invitation.org_name,
        'role', v_invitation.role,
        'expires_at', v_invitation.expires_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- RPC FUNCTION: Get Ticket Stats
-- ============================================
CREATE OR REPLACE FUNCTION public.get_ticket_stats(p_org_id UUID DEFAULT NULL)
RETURNS JSON AS $$
DECLARE
    v_user_profile RECORD;
    v_stats RECORD;
    v_filter_org_id UUID;
BEGIN
    -- Get current user's profile
    SELECT * INTO v_user_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Profile not found');
    END IF;

    -- Determine org filter based on role
    IF v_user_profile.role IN ('support_agent', 'support_admin') THEN
        v_filter_org_id := p_org_id; -- Can filter by any org or see all
    ELSE
        v_filter_org_id := v_user_profile.org_id; -- Can only see own org
    END IF;

    -- Get stats
    SELECT
        COUNT(*) FILTER (WHERE status = 'open') as open_count,
        COUNT(*) FILTER (WHERE status = 'in_progress') as in_progress_count,
        COUNT(*) FILTER (WHERE status = 'done') as done_count,
        COUNT(*) as total_count
    INTO v_stats
    FROM public.tickets
    WHERE (v_filter_org_id IS NULL OR org_id = v_filter_org_id);

    RETURN json_build_object(
        'success', true,
        'open', v_stats.open_count,
        'in_progress', v_stats.in_progress_count,
        'done', v_stats.done_count,
        'total', v_stats.total_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- RPC FUNCTION: Create Ticket with Event
-- ============================================
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
    IF p_priority NOT IN ('baixa', 'media', 'alta') THEN
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

-- ============================================
-- RPC FUNCTION: Update Ticket Status
-- ============================================
CREATE OR REPLACE FUNCTION public.update_ticket_status(
    p_ticket_id UUID,
    p_status TEXT
)
RETURNS JSON AS $$
DECLARE
    v_user_profile RECORD;
    v_ticket RECORD;
    v_old_status TEXT;
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
-- RPC FUNCTION: Assign Ticket
-- ============================================
CREATE OR REPLACE FUNCTION public.assign_ticket(
    p_ticket_id UUID,
    p_assignee_id UUID
)
RETURNS JSON AS $$
DECLARE
    v_user_profile RECORD;
    v_assignee_profile RECORD;
    v_ticket RECORD;
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
-- RPC FUNCTION: Add Comment
-- ============================================
CREATE OR REPLACE FUNCTION public.add_ticket_comment(
    p_ticket_id UUID,
    p_body TEXT
)
RETURNS JSON AS $$
DECLARE
    v_user_profile RECORD;
    v_ticket RECORD;
    v_comment_id UUID;
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

-- Grant execute permissions on all functions
GRANT EXECUTE ON FUNCTION public.create_organization_on_signup TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_support_user TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_invitation TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_invitation TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_invitation_by_token TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_ticket_stats TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_ticket TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_ticket_status TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_ticket TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_ticket_comment TO authenticated;
