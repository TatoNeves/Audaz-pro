-- ============================================
-- AUDAZ PRO - TICKET SYSTEM MIGRATIONS
-- Migration 019: Idempotent Support User Creation
-- ============================================

-- Allows an existing auth user/profile to be promoted or repaired as support
-- without failing on profiles_pkey duplicate key errors.
CREATE OR REPLACE FUNCTION public.create_support_user(
    p_user_id UUID,
    p_full_name TEXT,
    p_role TEXT DEFAULT 'support_agent'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_role NOT IN ('support_agent', 'support_admin') THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Invalid role. Must be support_agent or support_admin'
        );
    END IF;

    INSERT INTO public.profiles (id, org_id, role, full_name)
    VALUES (p_user_id, NULL, p_role, trim(p_full_name))
    ON CONFLICT (id) DO UPDATE SET
        org_id = NULL,
        role = EXCLUDED.role,
        full_name = EXCLUDED.full_name,
        updated_at = NOW();

    RETURN json_build_object(
        'success', true,
        'profile_id', p_user_id,
        'role', p_role
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'error', SQLERRM
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_support_user(UUID, TEXT, TEXT) TO authenticated;
