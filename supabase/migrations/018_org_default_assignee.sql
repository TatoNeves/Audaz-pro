-- ============================================
-- AUDAZ PRO - TICKET SYSTEM MIGRATIONS
-- Migration 018: Organization Default Assignee
-- ============================================

ALTER TABLE public.organizations
ADD COLUMN IF NOT EXISTS default_assignee_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_organizations_default_assignee_id
ON public.organizations(default_assignee_id);

COMMENT ON COLUMN public.organizations.default_assignee_id IS 'Support user automatically assigned to new tickets for this organization';

CREATE OR REPLACE FUNCTION public.update_org_default_assignee(
    p_org_id UUID,
    p_assignee_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_role TEXT;
    v_assignee_role TEXT;
BEGIN
    SELECT role INTO v_user_role
    FROM public.profiles
    WHERE id = auth.uid();

    IF v_user_role != 'support_admin' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Only support admins can update default assignees'
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_org_id) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Organization not found');
    END IF;

    IF p_assignee_id IS NOT NULL THEN
        SELECT role INTO v_assignee_role
        FROM public.profiles
        WHERE id = p_assignee_id;

        IF v_assignee_role NOT IN ('support_agent', 'support_admin') THEN
            RETURN jsonb_build_object('success', false, 'error', 'Default assignee must be a support user');
        END IF;
    END IF;

    UPDATE public.organizations
    SET default_assignee_id = p_assignee_id
    WHERE id = p_org_id;

    RETURN jsonb_build_object('success', true);
END;
$$;

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
    ORDER BY o.name;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_ticket(
    p_type TEXT,
    p_title TEXT,
    p_description TEXT,
    p_priority TEXT,
    p_category TEXT DEFAULT NULL,
    p_attachment_url TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_org_id UUID;
    v_ticket_id UUID;
    v_can_create JSONB;
    v_default_assignee_id UUID;
    v_default_assignee_name TEXT;
BEGIN
    v_user_id := auth.uid();

    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
    END IF;

    SELECT p.org_id, o.default_assignee_id
    INTO v_org_id, v_default_assignee_id
    FROM public.profiles p
    JOIN public.organizations o ON o.id = p.org_id
    WHERE p.id = v_user_id;

    IF v_org_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'User has no organization');
    END IF;

    IF v_default_assignee_id IS NOT NULL THEN
        SELECT full_name INTO v_default_assignee_name
        FROM public.profiles
        WHERE id = v_default_assignee_id
        AND role IN ('support_agent', 'support_admin');

        IF v_default_assignee_name IS NULL THEN
            v_default_assignee_id := NULL;
        END IF;
    END IF;

    v_can_create := public.can_create_ticket(v_org_id);

    IF NOT (v_can_create->>'allowed')::boolean THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', v_can_create->>'reason',
            'limit_reached', true,
            'limit', (v_can_create->>'limit')::integer,
            'used', (v_can_create->>'used')::integer,
            'extra_tasks', (v_can_create->>'extra_tasks')::integer
        );
    END IF;

    IF (v_can_create->>'using_extra')::boolean THEN
        UPDATE public.organizations
        SET extra_tasks = extra_tasks - 1
        WHERE id = v_org_id AND extra_tasks > 0;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'error', 'Monthly request limit reached');
        END IF;
    END IF;

    INSERT INTO public.tickets (
        org_id,
        type,
        title,
        description,
        priority,
        category,
        attachment_url,
        created_by,
        assigned_to
    )
    VALUES (
        v_org_id,
        p_type,
        p_title,
        p_description,
        p_priority,
        p_category,
        p_attachment_url,
        v_user_id,
        v_default_assignee_id
    )
    RETURNING id INTO v_ticket_id;

    INSERT INTO public.ticket_events (ticket_id, org_id, actor_id, event_type, payload)
    VALUES (v_ticket_id, v_org_id, v_user_id, 'created', jsonb_build_object('title', p_title));

    IF v_default_assignee_id IS NOT NULL THEN
        INSERT INTO public.ticket_events (ticket_id, org_id, actor_id, event_type, payload)
        VALUES (
            v_ticket_id,
            v_org_id,
            v_user_id,
            'assigned',
            jsonb_build_object(
                'assigned_to', v_default_assignee_id,
                'assignee_name', v_default_assignee_name,
                'automatic', true
            )
        );

        INSERT INTO public.ticket_collaborators (ticket_id, user_id, role, added_by)
        VALUES (v_ticket_id, v_default_assignee_id, 'assignee', v_user_id)
        ON CONFLICT (ticket_id, user_id) DO UPDATE SET role = 'assignee';
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'ticket_id', v_ticket_id,
        'assigned_to', v_default_assignee_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_org_default_assignee(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_organizations_with_usage() TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_ticket(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
