-- ============================================
-- FUNCTION: GET USER EMAIL
-- Returns the email of a user by their ID
-- Used for email notifications
-- ============================================

CREATE OR REPLACE FUNCTION public.get_user_email(user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_email TEXT;
BEGIN
    -- Get email from auth.users
    SELECT email INTO v_email
    FROM auth.users
    WHERE id = user_id;

    RETURN v_email;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.get_user_email(UUID) TO authenticated;
