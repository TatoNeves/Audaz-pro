-- ============================================
-- Migration 009: Fix Profile Visibility
-- ============================================
-- Problem: Clients cannot see support agent profiles because RLS policies
-- only allow viewing profiles from the same organization. Support agents
-- have org_id = NULL, so their profiles are invisible to clients.
--
-- Solution: Add policies allowing clients to see support profiles.
-- ============================================

-- Allow clients to view support profiles (for seeing comment authors)
DROP POLICY IF EXISTS "Clients can view support profiles" ON public.profiles;
CREATE POLICY "Clients can view support profiles"
    ON public.profiles FOR SELECT
    USING (
        role IN ('support_agent', 'support_admin')
        AND public.get_my_role() IN ('client_admin', 'client_user')
    );

-- Also allow users to see their own profile
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
CREATE POLICY "Users can view own profile"
    ON public.profiles FOR SELECT
    USING (id = auth.uid());
