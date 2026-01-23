-- ============================================
-- AUDAZ PRO - TICKET SYSTEM MIGRATIONS
-- Migration 003: Row Level Security Policies
-- ============================================

-- ============================================
-- ENABLE RLS ON ALL TABLES
-- ============================================
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;

-- ============================================
-- HELPER FUNCTION: Get current user's role
-- ============================================
CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS TEXT AS $$
BEGIN
    RETURN (SELECT role FROM public.profiles WHERE id = auth.uid());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ============================================
-- HELPER FUNCTION: Get current user's org_id
-- ============================================
CREATE OR REPLACE FUNCTION public.get_my_org_id()
RETURNS UUID AS $$
BEGIN
    RETURN (SELECT org_id FROM public.profiles WHERE id = auth.uid());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ============================================
-- HELPER FUNCTION: Check if user is support
-- ============================================
CREATE OR REPLACE FUNCTION public.is_support()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN (SELECT role IN ('support_agent', 'support_admin') FROM public.profiles WHERE id = auth.uid());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ============================================
-- ORGANIZATIONS POLICIES
-- ============================================

-- Users can see their own organization
DROP POLICY IF EXISTS "Users can view own organization" ON public.organizations;
CREATE POLICY "Users can view own organization"
    ON public.organizations FOR SELECT
    USING (id = public.get_my_org_id());

-- Support can see all organizations
DROP POLICY IF EXISTS "Support can view all organizations" ON public.organizations;
CREATE POLICY "Support can view all organizations"
    ON public.organizations FOR SELECT
    USING (public.is_support());

-- ============================================
-- PROFILES POLICIES
-- ============================================

-- Users can view their own profile
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
CREATE POLICY "Users can view own profile"
    ON public.profiles FOR SELECT
    USING (id = auth.uid());

-- Users can update their own profile (limited fields)
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

-- Client admins can view profiles in their org
DROP POLICY IF EXISTS "Client admins can view org profiles" ON public.profiles;
CREATE POLICY "Client admins can view org profiles"
    ON public.profiles FOR SELECT
    USING (
        org_id = public.get_my_org_id()
        AND public.get_my_role() = 'client_admin'
    );

-- Client users can view profiles in their org (for seeing who created tickets)
DROP POLICY IF EXISTS "Client users can view org profiles" ON public.profiles;
CREATE POLICY "Client users can view org profiles"
    ON public.profiles FOR SELECT
    USING (
        org_id = public.get_my_org_id()
        AND public.get_my_role() = 'client_user'
    );

-- Support can view all profiles
DROP POLICY IF EXISTS "Support can view all profiles" ON public.profiles;
CREATE POLICY "Support can view all profiles"
    ON public.profiles FOR SELECT
    USING (public.is_support());

-- Allow profile creation during signup (via RPC, but backup policy)
DROP POLICY IF EXISTS "Allow profile creation" ON public.profiles;
CREATE POLICY "Allow profile creation"
    ON public.profiles FOR INSERT
    WITH CHECK (id = auth.uid());

-- ============================================
-- TICKETS POLICIES
-- ============================================

-- Clients can view tickets from their organization
DROP POLICY IF EXISTS "Clients can view org tickets" ON public.tickets;
CREATE POLICY "Clients can view org tickets"
    ON public.tickets FOR SELECT
    USING (
        org_id = public.get_my_org_id()
        AND public.get_my_role() IN ('client_admin', 'client_user')
    );

-- Clients can create tickets for their organization
DROP POLICY IF EXISTS "Clients can create tickets" ON public.tickets;
CREATE POLICY "Clients can create tickets"
    ON public.tickets FOR INSERT
    WITH CHECK (
        org_id = public.get_my_org_id()
        AND created_by = auth.uid()
        AND public.get_my_role() IN ('client_admin', 'client_user')
    );

-- Clients can update their own tickets (limited)
DROP POLICY IF EXISTS "Clients can update own tickets" ON public.tickets;
CREATE POLICY "Clients can update own tickets"
    ON public.tickets FOR UPDATE
    USING (
        org_id = public.get_my_org_id()
        AND public.get_my_role() IN ('client_admin', 'client_user')
    )
    WITH CHECK (
        org_id = public.get_my_org_id()
    );

-- Support can view all tickets
DROP POLICY IF EXISTS "Support can view all tickets" ON public.tickets;
CREATE POLICY "Support can view all tickets"
    ON public.tickets FOR SELECT
    USING (public.is_support());

-- Support can update all tickets
DROP POLICY IF EXISTS "Support can update all tickets" ON public.tickets;
CREATE POLICY "Support can update all tickets"
    ON public.tickets FOR UPDATE
    USING (public.is_support());

-- ============================================
-- TICKET COMMENTS POLICIES
-- ============================================

-- Clients can view comments on their org's tickets
DROP POLICY IF EXISTS "Clients can view org comments" ON public.ticket_comments;
CREATE POLICY "Clients can view org comments"
    ON public.ticket_comments FOR SELECT
    USING (
        org_id = public.get_my_org_id()
        AND public.get_my_role() IN ('client_admin', 'client_user')
    );

-- Clients can create comments on their org's tickets
DROP POLICY IF EXISTS "Clients can create comments" ON public.ticket_comments;
CREATE POLICY "Clients can create comments"
    ON public.ticket_comments FOR INSERT
    WITH CHECK (
        org_id = public.get_my_org_id()
        AND author_id = auth.uid()
        AND public.get_my_role() IN ('client_admin', 'client_user')
    );

-- Support can view all comments
DROP POLICY IF EXISTS "Support can view all comments" ON public.ticket_comments;
CREATE POLICY "Support can view all comments"
    ON public.ticket_comments FOR SELECT
    USING (public.is_support());

-- Support can create comments on any ticket
DROP POLICY IF EXISTS "Support can create comments" ON public.ticket_comments;
CREATE POLICY "Support can create comments"
    ON public.ticket_comments FOR INSERT
    WITH CHECK (
        author_id = auth.uid()
        AND public.is_support()
    );

-- ============================================
-- TICKET EVENTS POLICIES
-- ============================================

-- Clients can view events on their org's tickets
DROP POLICY IF EXISTS "Clients can view org events" ON public.ticket_events;
CREATE POLICY "Clients can view org events"
    ON public.ticket_events FOR SELECT
    USING (
        org_id = public.get_my_org_id()
        AND public.get_my_role() IN ('client_admin', 'client_user')
    );

-- Clients can create events on their org's tickets (via RPC mostly)
DROP POLICY IF EXISTS "Clients can create events" ON public.ticket_events;
CREATE POLICY "Clients can create events"
    ON public.ticket_events FOR INSERT
    WITH CHECK (
        org_id = public.get_my_org_id()
        AND actor_id = auth.uid()
        AND public.get_my_role() IN ('client_admin', 'client_user')
    );

-- Support can view all events
DROP POLICY IF EXISTS "Support can view all events" ON public.ticket_events;
CREATE POLICY "Support can view all events"
    ON public.ticket_events FOR SELECT
    USING (public.is_support());

-- Support can create events on any ticket
DROP POLICY IF EXISTS "Support can create events" ON public.ticket_events;
CREATE POLICY "Support can create events"
    ON public.ticket_events FOR INSERT
    WITH CHECK (
        actor_id = auth.uid()
        AND public.is_support()
    );

-- ============================================
-- INVITATIONS POLICIES
-- ============================================

-- Client admins can view invitations from their org
DROP POLICY IF EXISTS "Client admins can view org invitations" ON public.invitations;
CREATE POLICY "Client admins can view org invitations"
    ON public.invitations FOR SELECT
    USING (
        org_id = public.get_my_org_id()
        AND public.get_my_role() = 'client_admin'
    );

-- Client admins can create invitations for their org (via RPC mostly)
DROP POLICY IF EXISTS "Client admins can create invitations" ON public.invitations;
CREATE POLICY "Client admins can create invitations"
    ON public.invitations FOR INSERT
    WITH CHECK (
        org_id = public.get_my_org_id()
        AND created_by = auth.uid()
        AND public.get_my_role() = 'client_admin'
    );

-- Support admins can view all invitations
DROP POLICY IF EXISTS "Support admins can view all invitations" ON public.invitations;
CREATE POLICY "Support admins can view all invitations"
    ON public.invitations FOR SELECT
    USING (public.get_my_role() = 'support_admin');

-- ============================================
-- GRANT EXECUTE ON HELPER FUNCTIONS
-- ============================================
GRANT EXECUTE ON FUNCTION public.get_my_role TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_org_id TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_support TO authenticated;
