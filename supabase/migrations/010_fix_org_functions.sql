-- ============================================
-- AUDAZ PRO - TICKET SYSTEM MIGRATIONS
-- Migration 010: Fix Organization Management Functions
-- Fixes ambiguous column references and missing email column
-- ============================================

-- ============================================
-- 1. FIX: GET ORGANIZATION MEMBERS (Support)
-- Fixed ambiguous 'role' reference and email column
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
    SELECT pr.role INTO v_user_role
    FROM public.profiles pr
    WHERE pr.id = auth.uid();

    IF v_user_role NOT IN ('support_agent', 'support_admin') THEN
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

-- ============================================
-- 2. FIX: GET PENDING INVITATIONS FOR ORG (Support)
-- Fixed ambiguous 'role' reference
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
    SELECT pr.role INTO v_user_role
    FROM public.profiles pr
    WHERE pr.id = auth.uid();

    IF v_user_role NOT IN ('support_agent', 'support_admin') THEN
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

-- ============================================
-- 3. FIX: INVITE MEMBER TO ORGANIZATION (Support Admin)
-- Fixed email column reference (profiles doesn't have email)
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

    -- Check if user already exists in this organization (using auth.users for email)
    IF EXISTS (
        SELECT 1 FROM public.profiles p
        JOIN auth.users u ON u.id = p.id
        WHERE lower(u.email) = lower(trim(p_email))
        AND p.org_id = p_org_id
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
