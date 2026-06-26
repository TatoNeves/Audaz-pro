-- ============================================
-- AUDAZ PRO - TICKET SYSTEM MIGRATIONS
-- Migration 016: Ticket Request Units
-- ============================================

-- Each ticket starts as one billable/request unit, but support can adjust it
-- when one customer ticket contains multiple distinct changes.
ALTER TABLE public.tickets
ADD COLUMN IF NOT EXISTS request_units INTEGER NOT NULL DEFAULT 1;

ALTER TABLE public.tickets
DROP CONSTRAINT IF EXISTS tickets_request_units_check;

ALTER TABLE public.tickets
ADD CONSTRAINT tickets_request_units_check
CHECK (request_units > 0 AND request_units <= 1000);

COMMENT ON COLUMN public.tickets.request_units IS 'Number of monthly request units consumed by this ticket';
COMMENT ON COLUMN public.organization_usage.tickets_created IS 'Monthly request units consumed by the organization';

-- Allow audit events for request unit adjustments.
ALTER TABLE public.ticket_events
DROP CONSTRAINT IF EXISTS ticket_events_event_type_check;

ALTER TABLE public.ticket_events
ADD CONSTRAINT ticket_events_event_type_check
CHECK (event_type IN (
    'created',
    'status_changed',
    'assigned',
    'commented',
    'priority_changed',
    'request_units_changed'
));

-- Count the ticket's request units instead of always counting one ticket.
CREATE OR REPLACE FUNCTION public.increment_org_usage()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_month TEXT;
    v_units INTEGER;
BEGIN
    v_current_month := to_char(NOW(), 'YYYY-MM');
    v_units := GREATEST(COALESCE(NEW.request_units, 1), 1);

    INSERT INTO public.organization_usage (org_id, month_year, tickets_created)
    VALUES (NEW.org_id, v_current_month, v_units)
    ON CONFLICT (org_id, month_year)
    DO UPDATE SET
        tickets_created = organization_usage.tickets_created + v_units,
        updated_at = NOW();

    RETURN NEW;
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

    v_old_units := GREATEST(COALESCE(v_ticket.request_units, 1), 1);
    v_delta := p_request_units - v_old_units;

    IF v_delta = 0 THEN
        RETURN jsonb_build_object(
            'success', true,
            'ticket_id', p_ticket_id,
            'old_units', v_old_units,
            'new_units', p_request_units,
            'delta', 0
        );
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
        jsonb_build_object(
            'from', v_old_units,
            'to', p_request_units,
            'delta', v_delta,
            'reason', NULLIF(trim(COALESCE(p_reason, '')), '')
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'ticket_id', p_ticket_id,
        'old_units', v_old_units,
        'new_units', p_request_units,
        'delta', v_delta
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_ticket_request_units(UUID, INTEGER, TEXT) TO authenticated;
