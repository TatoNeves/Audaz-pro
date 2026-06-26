-- ============================================
-- AUDAZ PRO - TICKET SYSTEM MIGRATIONS
-- Migration 020: Support Agent Invites and Scoped Access
-- ============================================

-- Support technician invites reuse the invitations table. For support_agent
-- rows, org_id means the organization the technician will be assigned to,
-- not client membership.
ALTER TABLE public.invitations
DROP CONSTRAINT IF EXISTS invitations_role_check;

ALTER TABLE public.invitations
ADD CONSTRAINT invitations_role_check
CHECK (role IN ('client_user', 'client_admin', 'support_agent'));

COMMENT ON COLUMN public.invitations.org_id IS 'Client organization for client invites; initial assigned organization for support_agent invites';

CREATE OR REPLACE FUNCTION public.is_support_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
BEGIN
    RETURN (
        SELECT role = 'support_admin'
        FROM public.profiles
        WHERE id = auth.uid()
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.can_support_access_org(p_org_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_role TEXT;
BEGIN
    SELECT role INTO v_role
    FROM public.profiles
    WHERE id = auth.uid();

    IF v_role = 'support_admin' THEN
        RETURN true;
    END IF;

    IF v_role != 'support_agent' THEN
        RETURN false;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM public.organizations o
        WHERE o.id = p_org_id
        AND o.default_assignee_id = auth.uid()
    )
    OR EXISTS (
        SELECT 1
        FROM public.tickets t
        WHERE t.org_id = p_org_id
        AND (
            t.assigned_to = auth.uid()
            OR EXISTS (
                SELECT 1
                FROM public.ticket_collaborators tc
                WHERE tc.ticket_id = t.id
                AND tc.user_id = auth.uid()
            )
        )
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.can_support_access_ticket(p_ticket_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_role TEXT;
BEGIN
    SELECT role INTO v_role
    FROM public.profiles
    WHERE id = auth.uid();

    IF v_role = 'support_admin' THEN
        RETURN true;
    END IF;

    IF v_role != 'support_agent' THEN
        RETURN false;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM public.tickets t
        JOIN public.organizations o ON o.id = t.org_id
        WHERE t.id = p_ticket_id
        AND (
            t.assigned_to = auth.uid()
            OR o.default_assignee_id = auth.uid()
            OR EXISTS (
                SELECT 1
                FROM public.ticket_collaborators tc
                WHERE tc.ticket_id = t.id
                AND tc.user_id = auth.uid()
            )
        )
    );
END;
$$;

-- ============================================
-- RLS: Support admins stay global. Support agents are scoped.
-- ============================================

DROP POLICY IF EXISTS "Support can view all organizations" ON public.organizations;
CREATE POLICY "Support can view assigned organizations"
    ON public.organizations FOR SELECT
    USING (public.can_support_access_org(id));

DROP POLICY IF EXISTS "Support can view all profiles" ON public.profiles;
CREATE POLICY "Support can view scoped profiles"
    ON public.profiles FOR SELECT
    USING (
        public.is_support_admin()
        OR id = auth.uid()
        OR (
            public.get_my_role() = 'support_agent'
            AND role IN ('support_agent', 'support_admin')
        )
        OR (
            org_id IS NOT NULL
            AND public.can_support_access_org(org_id)
        )
    );

DROP POLICY IF EXISTS "Support can view all tickets" ON public.tickets;
CREATE POLICY "Support can view scoped tickets"
    ON public.tickets FOR SELECT
    USING (public.can_support_access_ticket(id));

DROP POLICY IF EXISTS "Support can update all tickets" ON public.tickets;
CREATE POLICY "Support can update scoped tickets"
    ON public.tickets FOR UPDATE
    USING (public.can_support_access_ticket(id))
    WITH CHECK (public.can_support_access_ticket(id));

DROP POLICY IF EXISTS "Support can view all comments" ON public.ticket_comments;
CREATE POLICY "Support can view scoped comments"
    ON public.ticket_comments FOR SELECT
    USING (public.can_support_access_ticket(ticket_id));

DROP POLICY IF EXISTS "Support can create comments" ON public.ticket_comments;
CREATE POLICY "Support can create scoped comments"
    ON public.ticket_comments FOR INSERT
    WITH CHECK (
        author_id = auth.uid()
        AND public.can_support_access_ticket(ticket_id)
    );

DROP POLICY IF EXISTS "Support can view all events" ON public.ticket_events;
CREATE POLICY "Support can view scoped events"
    ON public.ticket_events FOR SELECT
    USING (public.can_support_access_ticket(ticket_id));

DROP POLICY IF EXISTS "Support can create events" ON public.ticket_events;
CREATE POLICY "Support can create scoped events"
    ON public.ticket_events FOR INSERT
    WITH CHECK (
        actor_id = auth.uid()
        AND public.can_support_access_ticket(ticket_id)
    );

DROP POLICY IF EXISTS "Support can view all collaborators" ON public.ticket_collaborators;
CREATE POLICY "Support can view scoped collaborators"
    ON public.ticket_collaborators FOR SELECT
    USING (public.can_support_access_ticket(ticket_id));

DROP POLICY IF EXISTS "Support can add collaborators" ON public.ticket_collaborators;
CREATE POLICY "Support can add scoped collaborators"
    ON public.ticket_collaborators FOR INSERT
    WITH CHECK (public.can_support_access_ticket(ticket_id));

DROP POLICY IF EXISTS "Support can remove collaborators" ON public.ticket_collaborators;
CREATE POLICY "Support can remove scoped collaborators"
    ON public.ticket_collaborators FOR DELETE
    USING (
        role != 'creator'
        AND public.can_support_access_ticket(ticket_id)
    );

-- ============================================
-- SUPPORT INVITES
-- ============================================

CREATE OR REPLACE FUNCTION public.invite_support_agent_for_org(
    p_org_id UUID,
    p_email TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_role TEXT;
    v_org_name TEXT;
    v_existing_user_id UUID;
    v_existing_full_name TEXT;
    v_invitation_id UUID;
    v_token TEXT;
    v_expires_at TIMESTAMPTZ;
BEGIN
    SELECT role INTO v_user_role
    FROM public.profiles
    WHERE id = auth.uid();

    IF v_user_role != 'support_admin' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Only support admins can invite technicians');
    END IF;

    IF p_email IS NULL OR trim(p_email) = '' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Email is required');
    END IF;

    SELECT name INTO v_org_name
    FROM public.organizations
    WHERE id = p_org_id;

    IF v_org_name IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Organization not found');
    END IF;

    SELECT u.id
    INTO v_existing_user_id
    FROM auth.users u
    WHERE lower(u.email) = lower(trim(p_email))
    LIMIT 1;

    IF v_existing_user_id IS NOT NULL THEN
        SELECT full_name
        INTO v_existing_full_name
        FROM public.profiles
        WHERE id = v_existing_user_id;

        INSERT INTO public.profiles (id, org_id, role, full_name)
        SELECT
            u.id,
            NULL,
            'support_agent',
            COALESCE(NULLIF(v_existing_full_name, ''), NULLIF(u.raw_user_meta_data->>'full_name', ''), split_part(lower(trim(p_email)), '@', 1))
        FROM auth.users u
        WHERE u.id = v_existing_user_id
        ON CONFLICT (id) DO UPDATE SET
            org_id = NULL,
            role = CASE
                WHEN public.profiles.role = 'support_admin' THEN 'support_admin'
                ELSE 'support_agent'
            END,
            full_name = COALESCE(NULLIF(public.profiles.full_name, ''), EXCLUDED.full_name),
            updated_at = NOW();

        UPDATE public.organizations
        SET default_assignee_id = v_existing_user_id
        WHERE id = p_org_id;

        RETURN jsonb_build_object(
            'success', true,
            'assigned_directly', true,
            'profile_id', v_existing_user_id,
            'org_id', p_org_id,
            'org_name', v_org_name,
            'email', lower(trim(p_email)),
            'message', 'Existing user assigned as default technician'
        );
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.invitations
        WHERE lower(email) = lower(trim(p_email))
        AND org_id = p_org_id
        AND role = 'support_agent'
        AND accepted_at IS NULL
        AND expires_at > NOW()
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'There is already a pending technician invitation for this email and organization');
    END IF;

    v_token := encode(gen_random_bytes(32), 'hex');
    v_expires_at := NOW() + INTERVAL '7 days';

    INSERT INTO public.invitations (org_id, email, role, token, expires_at, created_by)
    VALUES (p_org_id, lower(trim(p_email)), 'support_agent', v_token, v_expires_at, auth.uid())
    RETURNING id INTO v_invitation_id;

    RETURN jsonb_build_object(
        'success', true,
        'invitation_id', v_invitation_id,
        'token', v_token,
        'expires_at', v_expires_at,
        'org_id', p_org_id,
        'org_name', v_org_name,
        'email', lower(trim(p_email)),
        'role', 'support_agent',
        'message', 'Technician invitation created successfully'
    );
END;
$$;

-- Accept client and support-agent invitations.
CREATE OR REPLACE FUNCTION public.accept_invitation(
    p_token TEXT,
    p_user_id UUID,
    p_full_name TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_invitation RECORD;
    v_org_member_count INTEGER;
    v_max_members INTEGER := 4;
BEGIN
    SELECT *
    INTO v_invitation
    FROM public.invitations
    WHERE token = p_token
    AND accepted_at IS NULL;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Invitation not found or already used');
    END IF;

    IF v_invitation.expires_at < NOW() THEN
        RETURN json_build_object('success', false, 'error', 'Invitation expired');
    END IF;

    IF v_invitation.role IN ('client_admin', 'client_user') THEN
        SELECT COUNT(*) INTO v_org_member_count
        FROM public.profiles
        WHERE org_id = v_invitation.org_id;

        IF v_org_member_count >= v_max_members THEN
            RETURN json_build_object('success', false, 'error', 'Member limit reached (maximum 4 users per organization)');
        END IF;

        INSERT INTO public.profiles (id, org_id, role, full_name)
        VALUES (p_user_id, v_invitation.org_id, v_invitation.role, trim(p_full_name))
        ON CONFLICT (id) DO UPDATE SET
            org_id = EXCLUDED.org_id,
            role = EXCLUDED.role,
            full_name = EXCLUDED.full_name,
            updated_at = NOW();
    ELSIF v_invitation.role = 'support_agent' THEN
        INSERT INTO public.profiles (id, org_id, role, full_name)
        VALUES (p_user_id, NULL, 'support_agent', trim(p_full_name))
        ON CONFLICT (id) DO UPDATE SET
            org_id = NULL,
            role = CASE
                WHEN public.profiles.role = 'support_admin' THEN 'support_admin'
                ELSE 'support_agent'
            END,
            full_name = EXCLUDED.full_name,
            updated_at = NOW();

        UPDATE public.organizations
        SET default_assignee_id = p_user_id
        WHERE id = v_invitation.org_id;
    ELSE
        RETURN json_build_object('success', false, 'error', 'Invalid invitation role');
    END IF;

    UPDATE public.invitations
    SET accepted_at = NOW()
    WHERE id = v_invitation.id;

    RETURN json_build_object(
        'success', true,
        'org_id', v_invitation.org_id,
        'role', v_invitation.role
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- Harden manual support profile creation.
CREATE OR REPLACE FUNCTION public.create_support_user(
    p_user_id UUID,
    p_full_name TEXT,
    p_role TEXT DEFAULT 'support_agent'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_role TEXT;
BEGIN
    SELECT role INTO v_user_role
    FROM public.profiles
    WHERE id = auth.uid();

    IF v_user_role != 'support_admin' THEN
        RETURN json_build_object('success', false, 'error', 'Only support admins can create support users');
    END IF;

    IF p_role NOT IN ('support_agent', 'support_admin') THEN
        RETURN json_build_object('success', false, 'error', 'Invalid role. Must be support_agent or support_admin');
    END IF;

    INSERT INTO public.profiles (id, org_id, role, full_name)
    VALUES (p_user_id, NULL, p_role, trim(p_full_name))
    ON CONFLICT (id) DO UPDATE SET
        org_id = NULL,
        role = EXCLUDED.role,
        full_name = EXCLUDED.full_name,
        updated_at = NOW();

    RETURN json_build_object('success', true, 'profile_id', p_user_id, 'role', p_role);
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- ============================================
-- Scoped support RPCs
-- ============================================

DROP FUNCTION IF EXISTS public.get_organizations_with_usage();

CREATE OR REPLACE FUNCTION public.get_organizations_with_usage()
RETURNS TABLE (
    org_id UUID,
    org_name TEXT,
    plan_name TEXT,
    monthly_limit INTEGER,
    tickets_used_this_month INTEGER,
    total_tickets INTEGER,
    member_count INTEGER,
    created_at TIMESTAMPTZ,
    default_assignee_id UUID,
    default_assignee_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_role TEXT;
    v_current_month TEXT;
BEGIN
    SELECT role INTO v_user_role
    FROM public.profiles
    WHERE id = auth.uid();

    IF v_user_role NOT IN ('support_agent', 'support_admin') THEN
        RAISE EXCEPTION 'Access denied';
    END IF;

    v_current_month := to_char(NOW(), 'YYYY-MM');

    RETURN QUERY
    SELECT
        o.id AS org_id,
        o.name AS org_name,
        COALESCE(o.plan_name, 'Basic') AS plan_name,
        COALESCE(o.monthly_request_limit, 10) AS monthly_limit,
        COALESCE(ou.tickets_created, 0) AS tickets_used_this_month,
        (SELECT COUNT(*)::INTEGER FROM public.tickets t WHERE t.org_id = o.id) AS total_tickets,
        (SELECT COUNT(*)::INTEGER FROM public.profiles p WHERE p.org_id = o.id) AS member_count,
        o.created_at,
        o.default_assignee_id,
        assignee.full_name AS default_assignee_name
    FROM public.organizations o
    LEFT JOIN public.organization_usage ou ON o.id = ou.org_id AND ou.month_year = v_current_month
    LEFT JOIN public.profiles assignee ON assignee.id = o.default_assignee_id
    WHERE public.can_support_access_org(o.id)
    ORDER BY o.name;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_org_members_by_support(p_org_id UUID)
RETURNS TABLE (
    member_id UUID,
    full_name TEXT,
    email TEXT,
    role TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_role TEXT;
BEGIN
    SELECT pr.role INTO v_user_role
    FROM public.profiles pr
    WHERE pr.id = auth.uid();

    IF v_user_role NOT IN ('support_agent', 'support_admin') OR NOT public.can_support_access_org(p_org_id) THEN
        RAISE EXCEPTION 'Access denied';
    END IF;

    RETURN QUERY
    SELECT
        p.id AS member_id,
        p.full_name::TEXT,
        u.email::TEXT,
        p.role::TEXT,
        p.created_at
    FROM public.profiles p
    JOIN auth.users u ON u.id = p.id
    WHERE p.org_id = p_org_id
    ORDER BY p.created_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_org_invitations_by_support(p_org_id UUID)
RETURNS TABLE (
    invitation_id UUID,
    email TEXT,
    role TEXT,
    token TEXT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ,
    status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_role TEXT;
BEGIN
    SELECT pr.role INTO v_user_role
    FROM public.profiles pr
    WHERE pr.id = auth.uid();

    IF v_user_role NOT IN ('support_agent', 'support_admin') OR NOT public.can_support_access_org(p_org_id) THEN
        RAISE EXCEPTION 'Access denied';
    END IF;

    RETURN QUERY
    SELECT
        i.id AS invitation_id,
        i.email::TEXT,
        i.role::TEXT,
        i.token::TEXT,
        i.expires_at,
        i.created_at,
        CASE
            WHEN i.accepted_at IS NOT NULL THEN 'accepted'
            WHEN i.expires_at < NOW() THEN 'expired'
            ELSE 'pending'
        END::TEXT AS status
    FROM public.invitations i
    WHERE i.org_id = p_org_id
    ORDER BY i.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_ticket_stats(p_org_id UUID DEFAULT NULL)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_profile RECORD;
    v_stats RECORD;
BEGIN
    SELECT * INTO v_user_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Profile not found');
    END IF;

    SELECT
        COUNT(*) FILTER (WHERE status = 'open') as open_count,
        COUNT(*) FILTER (WHERE status = 'in_progress') as in_progress_count,
        COUNT(*) FILTER (WHERE status = 'done') as done_count,
        COUNT(*) as total_count
    INTO v_stats
    FROM public.tickets t
    WHERE
        CASE
            WHEN v_user_profile.role = 'support_admin' THEN (p_org_id IS NULL OR t.org_id = p_org_id)
            WHEN v_user_profile.role = 'support_agent' THEN (p_org_id IS NULL OR t.org_id = p_org_id) AND public.can_support_access_ticket(t.id)
            ELSE t.org_id = v_user_profile.org_id
        END;

    RETURN json_build_object(
        'success', true,
        'open', v_stats.open_count,
        'in_progress', v_stats.in_progress_count,
        'done', v_stats.done_count,
        'total', v_stats.total_count
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_ticket(
    p_ticket_id UUID,
    p_assignee_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_profile RECORD;
    v_ticket RECORD;
    v_assignee_profile RECORD;
    v_old_assignee UUID;
BEGIN
    SELECT * INTO v_user_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT FOUND OR v_user_profile.role NOT IN ('support_agent', 'support_admin') THEN
        RETURN json_build_object('success', false, 'error', 'Only support can assign tickets');
    END IF;

    IF NOT public.can_support_access_ticket(p_ticket_id) THEN
        RETURN json_build_object('success', false, 'error', 'Access denied');
    END IF;

    SELECT * INTO v_ticket
    FROM public.tickets
    WHERE id = p_ticket_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Ticket not found');
    END IF;

    SELECT * INTO v_assignee_profile
    FROM public.profiles
    WHERE id = p_assignee_id
    AND role IN ('support_agent', 'support_admin');

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Assignee must be a support user');
    END IF;

    v_old_assignee := v_ticket.assigned_to;

    UPDATE public.tickets
    SET assigned_to = p_assignee_id
    WHERE id = p_ticket_id;

    INSERT INTO public.ticket_events (ticket_id, org_id, actor_id, event_type, payload)
    VALUES (
        p_ticket_id,
        v_ticket.org_id,
        v_user_profile.id,
        'assigned',
        json_build_object('assigned_to', p_assignee_id, 'assignee_name', v_assignee_profile.full_name)
    );

    INSERT INTO public.ticket_collaborators (ticket_id, user_id, role, added_by)
    VALUES (p_ticket_id, p_assignee_id, 'assignee', v_user_profile.id)
    ON CONFLICT (ticket_id, user_id) DO UPDATE SET role = 'assignee';

    IF v_old_assignee IS NOT NULL AND v_old_assignee != p_assignee_id THEN
        UPDATE public.ticket_collaborators
        SET role = 'manual'
        WHERE ticket_id = p_ticket_id
        AND user_id = v_old_assignee
        AND role = 'assignee';
    END IF;

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
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

CREATE OR REPLACE FUNCTION public.add_ticket_comment(
    p_ticket_id UUID,
    p_body TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_profile RECORD;
    v_ticket RECORD;
    v_comment_id UUID;
    v_mentioned_name TEXT;
    v_mentioned_user RECORD;
    v_collaborator RECORD;
BEGIN
    SELECT * INTO v_user_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Profile not found');
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

    INSERT INTO public.ticket_comments (ticket_id, org_id, author_id, body)
    VALUES (p_ticket_id, v_ticket.org_id, v_user_profile.id, p_body)
    RETURNING id INTO v_comment_id;

    INSERT INTO public.ticket_events (ticket_id, org_id, actor_id, event_type, payload)
    VALUES (p_ticket_id, v_ticket.org_id, v_user_profile.id, 'commented', json_build_object('comment_id', v_comment_id));

    FOR v_mentioned_name IN
        SELECT DISTINCT trim(match[1])
        FROM regexp_matches(p_body, '@([A-Za-zÀ-ÿ]+ [A-Za-zÀ-ÿ]+)', 'g') AS match
    LOOP
        SELECT * INTO v_mentioned_user
        FROM public.profiles
        WHERE full_name ILIKE v_mentioned_name
        AND (
            org_id = v_ticket.org_id
            OR role IN ('support_agent', 'support_admin')
        )
        LIMIT 1;

        IF FOUND THEN
            INSERT INTO public.ticket_collaborators (ticket_id, user_id, role, added_by)
            VALUES (p_ticket_id, v_mentioned_user.id, 'mentioned', v_user_profile.id)
            ON CONFLICT (ticket_id, user_id) DO NOTHING;

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

    RETURN json_build_object('success', true, 'comment_id', v_comment_id);
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

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

    IF p_status NOT IN ('open', 'in_progress', 'done') THEN
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

CREATE OR REPLACE FUNCTION public.update_ticket_request_units(
    p_ticket_id UUID,
    p_request_units INTEGER,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_profile RECORD;
    v_ticket RECORD;
    v_old_units INTEGER;
    v_delta INTEGER;
    v_usage_month TEXT;
BEGIN
    SELECT * INTO v_user_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT FOUND OR v_user_profile.role NOT IN ('support_agent', 'support_admin') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Only support can update request units');
    END IF;

    IF p_request_units IS NULL OR p_request_units < 1 OR p_request_units > 1000 THEN
        RETURN jsonb_build_object('success', false, 'error', 'Request units must be between 1 and 1000');
    END IF;

    SELECT * INTO v_ticket
    FROM public.tickets
    WHERE id = p_ticket_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Ticket not found');
    END IF;

    IF NOT public.can_support_access_ticket(p_ticket_id) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Access denied');
    END IF;

    v_old_units := GREATEST(COALESCE(v_ticket.request_units, 1), 1);
    v_delta := p_request_units - v_old_units;

    IF v_delta = 0 THEN
        RETURN jsonb_build_object('success', true, 'ticket_id', p_ticket_id, 'old_units', v_old_units, 'new_units', p_request_units, 'delta', 0);
    END IF;

    UPDATE public.tickets
    SET request_units = p_request_units
    WHERE id = p_ticket_id;

    v_usage_month := to_char(v_ticket.created_at, 'YYYY-MM');

    INSERT INTO public.organization_usage (org_id, month_year, tickets_created)
    VALUES (v_ticket.org_id, v_usage_month, p_request_units)
    ON CONFLICT (org_id, month_year)
    DO UPDATE SET
        tickets_created = GREATEST(0, organization_usage.tickets_created + v_delta),
        updated_at = NOW();

    INSERT INTO public.ticket_events (ticket_id, org_id, actor_id, event_type, payload)
    VALUES (
        p_ticket_id,
        v_ticket.org_id,
        v_user_profile.id,
        'request_units_changed',
        jsonb_build_object('from', v_old_units, 'to', p_request_units, 'delta', v_delta, 'reason', NULLIF(trim(COALESCE(p_reason, '')), ''))
    );

    RETURN jsonb_build_object('success', true, 'ticket_id', p_ticket_id, 'old_units', v_old_units, 'new_units', p_request_units, 'delta', v_delta);
END;
$$;

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

    IF NOT public.can_support_access_ticket(p_ticket_id) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Access denied');
    END IF;

    IF v_ticket.due_date IS NOT DISTINCT FROM p_due_date THEN
        RETURN jsonb_build_object('success', true, 'ticket_id', p_ticket_id, 'old_due_date', v_ticket.due_date, 'new_due_date', p_due_date, 'changed', false);
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
        jsonb_build_object('from', v_ticket.due_date, 'to', p_due_date, 'reason', NULLIF(trim(COALESCE(p_reason, '')), ''))
    );

    RETURN jsonb_build_object('success', true, 'ticket_id', p_ticket_id, 'old_due_date', v_ticket.due_date, 'new_due_date', p_due_date, 'changed', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_ticket_collaborators(p_ticket_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_profile RECORD;
    v_ticket RECORD;
    v_collaborators JSON;
BEGIN
    SELECT * INTO v_user_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Profile not found');
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

    RETURN json_build_object('success', true, 'collaborators', COALESCE(v_collaborators, '[]'::json));
END;
$$;

CREATE OR REPLACE FUNCTION public.add_ticket_collaborator(
    p_ticket_id UUID,
    p_user_id UUID,
    p_role TEXT DEFAULT 'manual'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_profile RECORD;
    v_ticket RECORD;
    v_collaborator_id UUID;
BEGIN
    SELECT * INTO v_user_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Profile not found');
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

        IF NOT EXISTS (
            SELECT 1
            FROM public.profiles
            WHERE id = p_user_id
            AND org_id = v_ticket.org_id
        ) THEN
            RETURN json_build_object('success', false, 'error', 'User must be from the same organization');
        END IF;
    ELSIF NOT public.can_support_access_ticket(p_ticket_id) THEN
        RETURN json_build_object('success', false, 'error', 'Access denied');
    END IF;

    INSERT INTO public.ticket_collaborators (ticket_id, user_id, role, added_by)
    VALUES (p_ticket_id, p_user_id, p_role, v_user_profile.id)
    ON CONFLICT (ticket_id, user_id) DO UPDATE SET
        role = CASE
            WHEN ticket_collaborators.role IN ('creator', 'assignee') THEN ticket_collaborators.role
            ELSE EXCLUDED.role
        END
    RETURNING id INTO v_collaborator_id;

    RETURN json_build_object('success', true, 'collaborator_id', v_collaborator_id);
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_ticket_collaborator(
    p_ticket_id UUID,
    p_user_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_profile RECORD;
    v_ticket RECORD;
    v_collaborator RECORD;
BEGIN
    SELECT * INTO v_user_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Profile not found');
    END IF;

    SELECT * INTO v_collaborator
    FROM public.ticket_collaborators
    WHERE ticket_id = p_ticket_id
    AND user_id = p_user_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Collaborator not found');
    END IF;

    IF v_collaborator.role = 'creator' THEN
        RETURN json_build_object('success', false, 'error', 'Cannot remove ticket creator');
    END IF;

    SELECT * INTO v_ticket
    FROM public.tickets
    WHERE id = p_ticket_id;

    IF v_user_profile.role IN ('client_admin', 'client_user') THEN
        IF v_ticket.org_id != v_user_profile.org_id THEN
            RETURN json_build_object('success', false, 'error', 'Access denied');
        END IF;
        IF v_collaborator.role = 'assignee' THEN
            RETURN json_build_object('success', false, 'error', 'Cannot remove assignee');
        END IF;
    ELSIF NOT public.can_support_access_ticket(p_ticket_id) THEN
        RETURN json_build_object('success', false, 'error', 'Access denied');
    END IF;

    DELETE FROM public.ticket_collaborators
    WHERE ticket_id = p_ticket_id
    AND user_id = p_user_id;

    RETURN json_build_object('success', true);
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_ticket_comment(
    p_comment_id UUID,
    p_body TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_profile RECORD;
    v_comment RECORD;
    v_clean_body TEXT;
BEGIN
    v_clean_body := btrim(COALESCE(p_body, ''));

    IF v_clean_body = '' THEN
        RETURN json_build_object('success', false, 'error', 'Comment cannot be empty');
    END IF;

    SELECT * INTO v_user_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Profile not found');
    END IF;

    SELECT * INTO v_comment
    FROM public.ticket_comments
    WHERE id = p_comment_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Comment not found');
    END IF;

    IF v_user_profile.role IN ('support_agent', 'support_admin') THEN
        IF NOT public.can_support_access_ticket(v_comment.ticket_id) THEN
            RETURN json_build_object('success', false, 'error', 'Access denied');
        END IF;
    ELSE
        IF v_comment.author_id != v_user_profile.id THEN
            RETURN json_build_object('success', false, 'error', 'You can only edit your own comments');
        END IF;

        IF v_comment.org_id != v_user_profile.org_id THEN
            RETURN json_build_object('success', false, 'error', 'Access denied');
        END IF;
    END IF;

    UPDATE public.ticket_comments
    SET body = v_clean_body, updated_at = NOW(), edited_at = NOW()
    WHERE id = p_comment_id;

    RETURN json_build_object('success', true);
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_ticket_comment(
    p_comment_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_profile RECORD;
    v_comment RECORD;
BEGIN
    SELECT * INTO v_user_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Profile not found');
    END IF;

    SELECT * INTO v_comment
    FROM public.ticket_comments
    WHERE id = p_comment_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Comment not found');
    END IF;

    IF v_user_profile.role IN ('support_agent', 'support_admin') THEN
        IF NOT public.can_support_access_ticket(v_comment.ticket_id) THEN
            RETURN json_build_object('success', false, 'error', 'Access denied');
        END IF;
    ELSE
        IF v_comment.author_id != v_user_profile.id THEN
            RETURN json_build_object('success', false, 'error', 'You can only delete your own comments');
        END IF;

        IF v_comment.org_id != v_user_profile.org_id THEN
            RETURN json_build_object('success', false, 'error', 'Access denied');
        END IF;
    END IF;

    DELETE FROM public.ticket_events
    WHERE event_type = 'commented'
    AND payload->>'comment_id' = p_comment_id::TEXT;

    DELETE FROM public.ticket_comments
    WHERE id = p_comment_id;

    RETURN json_build_object('success', true);
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_support_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_support_access_org(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_support_access_ticket(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.invite_support_agent_for_org(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_invitation(TEXT, UUID, TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.create_support_user(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_organizations_with_usage() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_org_members_by_support(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_org_invitations_by_support(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_ticket_stats(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_ticket(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_ticket_comment(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_ticket_status(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_ticket_request_units(UUID, INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_ticket_due_date(UUID, DATE, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_ticket_collaborators(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_ticket_collaborator(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_ticket_collaborator(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_ticket_comment(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_ticket_comment(UUID) TO authenticated;
