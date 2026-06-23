-- Allow users to correct comments submitted by mistake.
-- Authors can edit/delete their own comments. Support can manage any comment.

ALTER TABLE public.ticket_comments
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW(),
ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ;

UPDATE public.ticket_comments
SET updated_at = created_at
WHERE updated_at IS NULL;

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

    IF NOT public.is_support() THEN
        IF v_comment.author_id != v_user_profile.id THEN
            RETURN json_build_object('success', false, 'error', 'You can only edit your own comments');
        END IF;

        IF v_comment.org_id != v_user_profile.org_id THEN
            RETURN json_build_object('success', false, 'error', 'Access denied');
        END IF;
    END IF;

    UPDATE public.ticket_comments
    SET
        body = v_clean_body,
        updated_at = NOW(),
        edited_at = NOW()
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

    IF NOT public.is_support() THEN
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

GRANT EXECUTE ON FUNCTION public.update_ticket_comment(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_ticket_comment(UUID) TO authenticated;
