-- ============================================
-- AUDAZ PRO - TICKET SYSTEM MIGRATIONS
-- Migration 005: Organization Management
-- ============================================

-- ============================================
-- 1. FUNCTION: CREATE ORGANIZATION (Support Admin)
-- ============================================
CREATE OR REPLACE FUNCTION public.create_organization_by_support(
    p_name TEXT,
    p_plan_name TEXT DEFAULT 'Basic',
    p_monthly_limit INTEGER DEFAULT 10
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_role TEXT;
    v_org_id UUID;
BEGIN
    -- Check if user is support_admin
    SELECT role INTO v_user_role
    FROM public.profiles
    WHERE id = auth.uid();

    IF v_user_role != 'support_admin' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Only support admins can create organizations'
        );
    END IF;

    -- Validate inputs
    IF p_name IS NULL OR trim(p_name) = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Organization name is required'
        );
    END IF;

    IF p_monthly_limit < 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Monthly limit must be non-negative'
        );
    END IF;

    -- Check if organization name already exists
    IF EXISTS (SELECT 1 FROM public.organizations WHERE lower(name) = lower(trim(p_name))) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'An organization with this name already exists'
        );
    END IF;

    -- Create organization
    INSERT INTO public.organizations (name, plan_name, monthly_request_limit)
    VALUES (trim(p_name), COALESCE(p_plan_name, 'Basic'), COALESCE(p_monthly_limit, 10))
    RETURNING id INTO v_org_id;

    RETURN jsonb_build_object(
        'success', true,
        'org_id', v_org_id,
        'message', 'Organization created successfully'
    );
END;
$$;

-- ============================================
-- 2. FUNCTION: DELETE ORGANIZATION (Support Admin)
-- Cascade deletes all related data
-- ============================================
CREATE OR REPLACE FUNCTION public.delete_organization_by_support(p_org_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_role TEXT;
    v_org_name TEXT;
    v_ticket_count INTEGER;
    v_member_count INTEGER;
BEGIN
    -- Check if user is support_admin
    SELECT role INTO v_user_role
    FROM public.profiles
    WHERE id = auth.uid();

    IF v_user_role != 'support_admin' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Only support admins can delete organizations'
        );
    END IF;

    -- Get organization info
    SELECT name INTO v_org_name
    FROM public.organizations
    WHERE id = p_org_id;

    IF v_org_name IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Organization not found'
        );
    END IF;

    -- Get counts for logging
    SELECT COUNT(*) INTO v_ticket_count FROM public.tickets WHERE org_id = p_org_id;
    SELECT COUNT(*) INTO v_member_count FROM public.profiles WHERE org_id = p_org_id;

    -- Delete ticket events first (due to FK constraints)
    DELETE FROM public.ticket_events WHERE org_id = p_org_id;

    -- Delete ticket comments
    DELETE FROM public.ticket_comments WHERE ticket_id IN (
        SELECT id FROM public.tickets WHERE org_id = p_org_id
    );

    -- Delete tickets
    DELETE FROM public.tickets WHERE org_id = p_org_id;

    -- Delete organization usage
    DELETE FROM public.organization_usage WHERE org_id = p_org_id;

    -- Delete invitations
    DELETE FROM public.invitations WHERE org_id = p_org_id;

    -- Set profiles org_id to NULL (don't delete users)
    UPDATE public.profiles SET org_id = NULL WHERE org_id = p_org_id;

    -- Finally delete the organization
    DELETE FROM public.organizations WHERE id = p_org_id;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Organization deleted successfully',
        'deleted', jsonb_build_object(
            'org_name', v_org_name,
            'tickets', v_ticket_count,
            'members', v_member_count
        )
    );
END;
$$;

-- ============================================
-- 3. FUNCTION: INVITE MEMBER TO ORGANIZATION (Support Admin)
-- Creates invitation for a specific organization
-- ============================================
CREATE OR REPLACE FUNCTION public.invite_member_to_org(
    p_org_id UUID,
    p_email TEXT,
    p_role TEXT DEFAULT 'client_user'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_role TEXT;
    v_org_name TEXT;
    v_invitation_id UUID;
    v_token TEXT;
    v_expires_at TIMESTAMPTZ;
BEGIN
    -- Check if user is support_admin
    SELECT role INTO v_user_role
    FROM public.profiles
    WHERE id = auth.uid();

    IF v_user_role != 'support_admin' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Only support admins can invite members to organizations'
        );
    END IF;

    -- Validate email
    IF p_email IS NULL OR trim(p_email) = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Email is required'
        );
    END IF;

    -- Check if organization exists
    SELECT name INTO v_org_name
    FROM public.organizations
    WHERE id = p_org_id;

    IF v_org_name IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Organization not found'
        );
    END IF;

    -- Validate role
    IF p_role NOT IN ('client_admin', 'client_user') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Invalid role. Must be client_admin or client_user'
        );
    END IF;

    -- Check if user already exists in this organization
    IF EXISTS (
        SELECT 1 FROM public.profiles
        WHERE lower(email) = lower(trim(p_email))
        AND org_id = p_org_id
    ) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'This user is already a member of this organization'
        );
    END IF;

    -- Check if there's already a pending invitation for this email and org
    IF EXISTS (
        SELECT 1 FROM public.invitations
        WHERE lower(email) = lower(trim(p_email))
        AND org_id = p_org_id
        AND accepted_at IS NULL
        AND expires_at > NOW()
    ) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'There is already a pending invitation for this email'
        );
    END IF;

    -- Generate token and set expiration (7 days)
    v_token := encode(gen_random_bytes(32), 'hex');
    v_expires_at := NOW() + INTERVAL '7 days';

    -- Create invitation
    INSERT INTO public.invitations (org_id, email, role, token, expires_at, created_by)
    VALUES (p_org_id, lower(trim(p_email)), p_role, v_token, v_expires_at, auth.uid())
    RETURNING id INTO v_invitation_id;

    RETURN jsonb_build_object(
        'success', true,
        'invitation_id', v_invitation_id,
        'token', v_token,
        'expires_at', v_expires_at,
        'org_name', v_org_name,
        'email', lower(trim(p_email)),
        'message', 'Invitation created successfully'
    );
END;
$$;

-- ============================================
-- 4. FUNCTION: GET ORGANIZATION MEMBERS (Support)
-- ============================================
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
    -- Check if user is support
    SELECT role INTO v_user_role
    FROM public.profiles
    WHERE id = auth.uid();

    IF v_user_role NOT IN ('support_agent', 'support_admin') THEN
        RAISE EXCEPTION 'Access denied';
    END IF;

    RETURN QUERY
    SELECT
        p.id AS member_id,
        p.full_name,
        p.email,
        p.role,
        p.created_at
    FROM public.profiles p
    WHERE p.org_id = p_org_id
    ORDER BY p.created_at;
END;
$$;

-- ============================================
-- 5. FUNCTION: GET PENDING INVITATIONS FOR ORG (Support)
-- ============================================
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
    -- Check if user is support
    SELECT role INTO v_user_role
    FROM public.profiles
    WHERE id = auth.uid();

    IF v_user_role NOT IN ('support_agent', 'support_admin') THEN
        RAISE EXCEPTION 'Access denied';
    END IF;

    RETURN QUERY
    SELECT
        i.id AS invitation_id,
        i.email,
        i.role,
        i.token,
        i.expires_at,
        i.created_at,
        CASE
            WHEN i.accepted_at IS NOT NULL THEN 'accepted'
            WHEN i.expires_at < NOW() THEN 'expired'
            ELSE 'pending'
        END AS status
    FROM public.invitations i
    WHERE i.org_id = p_org_id
    ORDER BY i.created_at DESC;
END;
$$;

-- ============================================
-- 6. FUNCTION: CANCEL INVITATION (Support Admin)
-- ============================================
CREATE OR REPLACE FUNCTION public.cancel_invitation_by_support(p_invitation_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_role TEXT;
BEGIN
    -- Check if user is support_admin
    SELECT role INTO v_user_role
    FROM public.profiles
    WHERE id = auth.uid();

    IF v_user_role != 'support_admin' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Only support admins can cancel invitations'
        );
    END IF;

    -- Delete the invitation
    DELETE FROM public.invitations WHERE id = p_invitation_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Invitation not found'
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Invitation cancelled successfully'
    );
END;
$$;

-- ============================================
-- 7. GRANT PERMISSIONS
-- ============================================
GRANT EXECUTE ON FUNCTION public.create_organization_by_support(TEXT, TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_organization_by_support(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.invite_member_to_org(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_org_members_by_support(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_org_invitations_by_support(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_invitation_by_support(UUID) TO authenticated;
