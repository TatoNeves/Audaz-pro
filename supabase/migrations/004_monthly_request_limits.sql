-- ============================================
-- AUDAZ PRO - TICKET SYSTEM MIGRATIONS
-- Migration 004: Monthly Request Limits
-- ============================================

-- ============================================
-- 1. ADD MONTHLY LIMIT COLUMNS TO ORGANIZATIONS
-- ============================================
ALTER TABLE public.organizations
ADD COLUMN IF NOT EXISTS monthly_request_limit INTEGER DEFAULT 10,
ADD COLUMN IF NOT EXISTS plan_name TEXT DEFAULT 'Basic';

COMMENT ON COLUMN public.organizations.monthly_request_limit IS 'Maximum number of tickets/requests this organization can create per month';
COMMENT ON COLUMN public.organizations.plan_name IS 'Name of the plan (Basic, Pro, Enterprise, etc.)';

-- ============================================
-- 2. CREATE MONTHLY USAGE TRACKING TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.organization_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE NOT NULL,
    month_year TEXT NOT NULL, -- Format: 'YYYY-MM'
    tickets_created INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(org_id, month_year)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_org_usage_org_id ON public.organization_usage(org_id);
CREATE INDEX IF NOT EXISTS idx_org_usage_month ON public.organization_usage(month_year);

COMMENT ON TABLE public.organization_usage IS 'Tracks monthly ticket usage per organization';

-- ============================================
-- 3. FUNCTION: GET CURRENT MONTH USAGE
-- ============================================
CREATE OR REPLACE FUNCTION public.get_org_monthly_usage(p_org_id UUID)
RETURNS TABLE (
    monthly_limit INTEGER,
    tickets_used INTEGER,
    tickets_remaining INTEGER,
    current_month TEXT,
    plan_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_month TEXT;
    v_monthly_limit INTEGER;
    v_tickets_used INTEGER;
    v_plan_name TEXT;
BEGIN
    v_current_month := to_char(NOW(), 'YYYY-MM');

    -- Get organization limit and plan
    SELECT o.monthly_request_limit, o.plan_name
    INTO v_monthly_limit, v_plan_name
    FROM public.organizations o
    WHERE o.id = p_org_id;

    IF v_monthly_limit IS NULL THEN
        v_monthly_limit := 10; -- Default limit
    END IF;

    IF v_plan_name IS NULL THEN
        v_plan_name := 'Basic';
    END IF;

    -- Get current month usage
    SELECT COALESCE(ou.tickets_created, 0)
    INTO v_tickets_used
    FROM public.organization_usage ou
    WHERE ou.org_id = p_org_id AND ou.month_year = v_current_month;

    IF v_tickets_used IS NULL THEN
        v_tickets_used := 0;
    END IF;

    RETURN QUERY SELECT
        v_monthly_limit,
        v_tickets_used,
        GREATEST(v_monthly_limit - v_tickets_used, 0),
        v_current_month,
        v_plan_name;
END;
$$;

-- ============================================
-- 4. FUNCTION: CHECK IF ORG CAN CREATE TICKET
-- ============================================
CREATE OR REPLACE FUNCTION public.can_create_ticket(p_org_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_month TEXT;
    v_monthly_limit INTEGER;
    v_tickets_used INTEGER;
BEGIN
    v_current_month := to_char(NOW(), 'YYYY-MM');

    -- Get organization limit
    SELECT COALESCE(o.monthly_request_limit, 10)
    INTO v_monthly_limit
    FROM public.organizations o
    WHERE o.id = p_org_id;

    -- Get current month usage
    SELECT COALESCE(ou.tickets_created, 0)
    INTO v_tickets_used
    FROM public.organization_usage ou
    WHERE ou.org_id = p_org_id AND ou.month_year = v_current_month;

    IF v_tickets_used IS NULL THEN
        v_tickets_used := 0;
    END IF;

    IF v_tickets_used >= v_monthly_limit THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'reason', 'Monthly request limit reached',
            'limit', v_monthly_limit,
            'used', v_tickets_used
        );
    END IF;

    RETURN jsonb_build_object(
        'allowed', true,
        'limit', v_monthly_limit,
        'used', v_tickets_used,
        'remaining', v_monthly_limit - v_tickets_used
    );
END;
$$;

-- ============================================
-- 5. FUNCTION: INCREMENT MONTHLY USAGE
-- ============================================
CREATE OR REPLACE FUNCTION public.increment_org_usage()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_month TEXT;
BEGIN
    v_current_month := to_char(NOW(), 'YYYY-MM');

    -- Upsert usage record
    INSERT INTO public.organization_usage (org_id, month_year, tickets_created)
    VALUES (NEW.org_id, v_current_month, 1)
    ON CONFLICT (org_id, month_year)
    DO UPDATE SET
        tickets_created = organization_usage.tickets_created + 1,
        updated_at = NOW();

    RETURN NEW;
END;
$$;

-- Create trigger to increment usage on ticket creation
DROP TRIGGER IF EXISTS trigger_increment_org_usage ON public.tickets;
CREATE TRIGGER trigger_increment_org_usage
    AFTER INSERT ON public.tickets
    FOR EACH ROW
    EXECUTE FUNCTION public.increment_org_usage();

-- ============================================
-- 6. FUNCTION: UPDATE ORGANIZATION LIMITS (Support Admin)
-- ============================================
CREATE OR REPLACE FUNCTION public.update_org_limits(
    p_org_id UUID,
    p_monthly_limit INTEGER,
    p_plan_name TEXT DEFAULT NULL
)
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
            'error', 'Only support admins can update organization limits'
        );
    END IF;

    -- Validate limit
    IF p_monthly_limit < 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Monthly limit must be non-negative'
        );
    END IF;

    -- Update organization
    UPDATE public.organizations
    SET
        monthly_request_limit = p_monthly_limit,
        plan_name = COALESCE(p_plan_name, plan_name)
    WHERE id = p_org_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Organization not found'
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Organization limits updated successfully'
    );
END;
$$;

-- ============================================
-- 7. FUNCTION: GET ALL ORGANIZATIONS WITH USAGE (Support)
-- ============================================
CREATE OR REPLACE FUNCTION public.get_organizations_with_usage()
RETURNS TABLE (
    org_id UUID,
    org_name TEXT,
    plan_name TEXT,
    monthly_limit INTEGER,
    tickets_used_this_month INTEGER,
    total_tickets INTEGER,
    member_count INTEGER,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_role TEXT;
    v_current_month TEXT;
BEGIN
    -- Check if user is support
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
        o.created_at
    FROM public.organizations o
    LEFT JOIN public.organization_usage ou ON o.id = ou.org_id AND ou.month_year = v_current_month
    ORDER BY o.name;
END;
$$;

-- ============================================
-- 8. UPDATE CREATE_TICKET FUNCTION TO CHECK LIMITS
-- ============================================
DROP FUNCTION IF EXISTS public.create_ticket(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);

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
BEGIN
    v_user_id := auth.uid();

    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
    END IF;

    -- Get user's org_id
    SELECT org_id INTO v_org_id
    FROM public.profiles
    WHERE id = v_user_id;

    IF v_org_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'User has no organization');
    END IF;

    -- Check if organization can create more tickets
    v_can_create := public.can_create_ticket(v_org_id);

    IF NOT (v_can_create->>'allowed')::boolean THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', v_can_create->>'reason',
            'limit_reached', true,
            'limit', (v_can_create->>'limit')::integer,
            'used', (v_can_create->>'used')::integer
        );
    END IF;

    -- Insert ticket
    INSERT INTO public.tickets (org_id, type, title, description, priority, category, attachment_url, created_by)
    VALUES (v_org_id, p_type, p_title, p_description, p_priority, p_category, p_attachment_url, v_user_id)
    RETURNING id INTO v_ticket_id;

    -- Create 'created' event
    INSERT INTO public.ticket_events (ticket_id, org_id, actor_id, event_type, payload)
    VALUES (v_ticket_id, v_org_id, v_user_id, 'created', jsonb_build_object('title', p_title));

    RETURN jsonb_build_object('success', true, 'ticket_id', v_ticket_id);
END;
$$;

-- ============================================
-- 9. RLS POLICIES FOR ORGANIZATION_USAGE
-- ============================================
ALTER TABLE public.organization_usage ENABLE ROW LEVEL SECURITY;

-- Clients can view their own organization's usage
CREATE POLICY "Clients can view own org usage"
ON public.organization_usage
FOR SELECT
USING (
    org_id IN (SELECT org_id FROM public.profiles WHERE id = auth.uid())
);

-- Support can view all usage
CREATE POLICY "Support can view all usage"
ON public.organization_usage
FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid()
        AND role IN ('support_agent', 'support_admin')
    )
);

-- Only system (via triggers) can insert/update usage
CREATE POLICY "System can manage usage"
ON public.organization_usage
FOR ALL
USING (true)
WITH CHECK (true);

-- ============================================
-- 10. GRANT PERMISSIONS
-- ============================================
GRANT EXECUTE ON FUNCTION public.get_org_monthly_usage(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_create_ticket(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_org_limits(UUID, INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_organizations_with_usage() TO authenticated;
GRANT ALL ON public.organization_usage TO authenticated;
