-- ============================================
-- AUDAZ PRO - TICKET SYSTEM MIGRATIONS
-- Migration 013: Extra Tasks & Stripe Integration
-- ============================================

-- ============================================
-- 1. ADD EXTRA TASKS & STRIPE COLUMNS TO ORGANIZATIONS
-- ============================================
ALTER TABLE public.organizations
ADD COLUMN IF NOT EXISTS extra_tasks INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT;

COMMENT ON COLUMN public.organizations.extra_tasks IS 'Permanent extra tasks purchased via Stripe, consumed after monthly limit is exhausted';
COMMENT ON COLUMN public.organizations.stripe_customer_id IS 'Stripe customer ID for billing';

-- ============================================
-- 2. CREATE TASK PURCHASES TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.task_purchases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE NOT NULL,
    stripe_session_id TEXT UNIQUE NOT NULL,
    stripe_payment_intent_id TEXT,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    amount_paid INTEGER NOT NULL, -- in cents
    currency TEXT NOT NULL DEFAULT 'usd',
    status TEXT NOT NULL DEFAULT 'completed',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_task_purchases_org_id ON public.task_purchases(org_id);
CREATE INDEX IF NOT EXISTS idx_task_purchases_session_id ON public.task_purchases(stripe_session_id);

COMMENT ON TABLE public.task_purchases IS 'Audit log of extra tasks purchased via Stripe';

-- ============================================
-- 3. RLS FOR TASK_PURCHASES
-- ============================================
ALTER TABLE public.task_purchases ENABLE ROW LEVEL SECURITY;

-- Clients can view their own org's purchases
CREATE POLICY "Clients can view own org purchases"
ON public.task_purchases
FOR SELECT
USING (
    org_id IN (SELECT org_id FROM public.profiles WHERE id = auth.uid())
);

-- Support can view all purchases
CREATE POLICY "Support can view all purchases"
ON public.task_purchases
FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid()
        AND role IN ('support_agent', 'support_admin')
    )
);

-- ============================================
-- 4. UPDATE get_org_monthly_usage TO INCLUDE EXTRA TASKS
-- ============================================
DROP FUNCTION IF EXISTS public.get_org_monthly_usage(UUID);

CREATE OR REPLACE FUNCTION public.get_org_monthly_usage(p_org_id UUID)
RETURNS TABLE (
    monthly_limit INTEGER,
    tickets_used INTEGER,
    tickets_remaining INTEGER,
    current_month TEXT,
    plan_name TEXT,
    extra_tasks INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_month TEXT;
    v_monthly_limit INTEGER;
    v_tickets_used INTEGER;
    v_plan_name TEXT;
    v_extra_tasks INTEGER;
BEGIN
    v_current_month := to_char(NOW(), 'YYYY-MM');

    SELECT o.monthly_request_limit, o.plan_name, COALESCE(o.extra_tasks, 0)
    INTO v_monthly_limit, v_plan_name, v_extra_tasks
    FROM public.organizations o
    WHERE o.id = p_org_id;

    IF v_monthly_limit IS NULL THEN
        v_monthly_limit := 10;
    END IF;

    IF v_plan_name IS NULL THEN
        v_plan_name := 'Basic';
    END IF;

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
        v_plan_name,
        v_extra_tasks;
END;
$$;

-- ============================================
-- 5. UPDATE can_create_ticket TO CONSIDER EXTRA TASKS
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
    v_extra_tasks INTEGER;
BEGIN
    v_current_month := to_char(NOW(), 'YYYY-MM');

    SELECT COALESCE(o.monthly_request_limit, 10), COALESCE(o.extra_tasks, 0)
    INTO v_monthly_limit, v_extra_tasks
    FROM public.organizations o
    WHERE o.id = p_org_id;

    SELECT COALESCE(ou.tickets_created, 0)
    INTO v_tickets_used
    FROM public.organization_usage ou
    WHERE ou.org_id = p_org_id AND ou.month_year = v_current_month;

    IF v_tickets_used IS NULL THEN
        v_tickets_used := 0;
    END IF;

    -- Within monthly limit
    IF v_tickets_used < v_monthly_limit THEN
        RETURN jsonb_build_object(
            'allowed', true,
            'limit', v_monthly_limit,
            'used', v_tickets_used,
            'remaining', v_monthly_limit - v_tickets_used,
            'extra_tasks', v_extra_tasks,
            'using_extra', false
        );
    END IF;

    -- Monthly limit exhausted — check extra tasks
    IF v_extra_tasks > 0 THEN
        RETURN jsonb_build_object(
            'allowed', true,
            'limit', v_monthly_limit,
            'used', v_tickets_used,
            'remaining', 0,
            'extra_tasks', v_extra_tasks,
            'using_extra', true
        );
    END IF;

    RETURN jsonb_build_object(
        'allowed', false,
        'reason', 'Monthly request limit reached',
        'limit', v_monthly_limit,
        'used', v_tickets_used,
        'extra_tasks', 0
    );
END;
$$;

-- ============================================
-- 6. UPDATE create_ticket TO CONSUME EXTRA TASKS WHEN NEEDED
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

    SELECT org_id INTO v_org_id
    FROM public.profiles
    WHERE id = v_user_id;

    IF v_org_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'User has no organization');
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

    -- If using extra tasks, decrement the counter
    IF (v_can_create->>'using_extra')::boolean THEN
        UPDATE public.organizations
        SET extra_tasks = extra_tasks - 1
        WHERE id = v_org_id AND extra_tasks > 0;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'error', 'Monthly request limit reached');
        END IF;
    END IF;

    INSERT INTO public.tickets (org_id, type, title, description, priority, category, attachment_url, created_by)
    VALUES (v_org_id, p_type, p_title, p_description, p_priority, p_category, p_attachment_url, v_user_id)
    RETURNING id INTO v_ticket_id;

    INSERT INTO public.ticket_events (ticket_id, org_id, actor_id, event_type, payload)
    VALUES (v_ticket_id, v_org_id, v_user_id, 'created', jsonb_build_object('title', p_title));

    RETURN jsonb_build_object('success', true, 'ticket_id', v_ticket_id);
END;
$$;

-- ============================================
-- 7. FUNCTION: RECORD TASK PURCHASE (called by webhook)
-- Uses service role — no auth check needed
-- ============================================
CREATE OR REPLACE FUNCTION public.record_task_purchase(
    p_org_id UUID,
    p_stripe_session_id TEXT,
    p_stripe_payment_intent_id TEXT,
    p_quantity INTEGER,
    p_amount_paid INTEGER,
    p_currency TEXT DEFAULT 'usd'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_org_exists BOOLEAN;
BEGIN
    -- Verify org exists
    SELECT EXISTS(SELECT 1 FROM public.organizations WHERE id = p_org_id)
    INTO v_org_exists;

    IF NOT v_org_exists THEN
        RETURN jsonb_build_object('success', false, 'error', 'Organization not found');
    END IF;

    -- Prevent duplicate processing
    IF EXISTS(SELECT 1 FROM public.task_purchases WHERE stripe_session_id = p_stripe_session_id) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Session already processed');
    END IF;

    -- Record the purchase
    INSERT INTO public.task_purchases (
        org_id, stripe_session_id, stripe_payment_intent_id,
        quantity, amount_paid, currency, status
    )
    VALUES (
        p_org_id, p_stripe_session_id, p_stripe_payment_intent_id,
        p_quantity, p_amount_paid, p_currency, 'completed'
    );

    -- Add tasks to the organization
    UPDATE public.organizations
    SET extra_tasks = extra_tasks + p_quantity
    WHERE id = p_org_id;

    RETURN jsonb_build_object(
        'success', true,
        'quantity_added', p_quantity
    );
END;
$$;

-- ============================================
-- 8. FUNCTION: UPDATE STRIPE CUSTOMER ID
-- ============================================
CREATE OR REPLACE FUNCTION public.update_stripe_customer_id(
    p_org_id UUID,
    p_stripe_customer_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.organizations
    SET stripe_customer_id = p_stripe_customer_id
    WHERE id = p_org_id;

    RETURN jsonb_build_object('success', true);
END;
$$;

-- ============================================
-- 9. GRANT PERMISSIONS
-- ============================================
GRANT EXECUTE ON FUNCTION public.get_org_monthly_usage(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_create_ticket(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_task_purchase(UUID, TEXT, TEXT, INTEGER, INTEGER, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.update_stripe_customer_id(UUID, TEXT) TO service_role;
GRANT SELECT ON public.task_purchases TO authenticated;
