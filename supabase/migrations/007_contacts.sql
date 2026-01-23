-- ============================================
-- AUDAZ PRO - TICKET SYSTEM MIGRATIONS
-- Migration 007: Marketing form contacts table
-- ============================================

-- Create a table to store inbound marketing leads from the static site.
CREATE TABLE IF NOT EXISTS public.contacts (
    id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    company TEXT,
    email TEXT NOT NULL,
    phone TEXT,
    budget TEXT,
    message TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    read BOOLEAN DEFAULT FALSE
);

ALTER TABLE IF EXISTS public.contacts ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "Allow anonymous inserts" ON public.contacts
  FOR INSERT
  WITH CHECK (true);

CREATE POLICY IF NOT EXISTS "Allow authenticated reads" ON public.contacts
  FOR SELECT
  USING (auth.role() = 'authenticated');

GRANT INSERT ON public.contacts TO anon;
GRANT SELECT ON public.contacts TO authenticated;
