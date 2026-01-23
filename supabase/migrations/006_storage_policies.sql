-- ============================================
-- AUDAZ PRO - TICKET SYSTEM MIGRATIONS
-- Migration 006: Storage Policies for Attachments
-- ============================================

-- Enable Row Level Security on storage.objects (required before creating policies)
ALTER TABLE IF EXISTS storage.objects ENABLE ROW LEVEL SECURITY;

-- Allow authenticated clients to upload files into ticket-attachments
DROP POLICY IF EXISTS "Allow authenticated ticket attachments upload" ON storage.objects;
CREATE POLICY "Allow authenticated ticket attachments upload"
    ON storage.objects
    FOR INSERT
    WITH CHECK (
        bucket_id = 'ticket-attachments'
        AND auth.role() = 'authenticated'
    );

-- Allow authenticated clients to list/download files stored on ticket-attachments
DROP POLICY IF EXISTS "Allow authenticated ticket attachments read" ON storage.objects;
CREATE POLICY "Allow authenticated ticket attachments read"
    ON storage.objects
    FOR SELECT
    USING (
        bucket_id = 'ticket-attachments'
        AND auth.role() = 'authenticated'
    );

-- Optionally allow deletion if needed (keeps dataset clean)
DROP POLICY IF EXISTS "Allow authenticated ticket attachments delete" ON storage.objects;
CREATE POLICY "Allow authenticated ticket attachments delete"
    ON storage.objects
    FOR DELETE
    USING (
        bucket_id = 'ticket-attachments'
        AND auth.role() = 'authenticated'
    );

GRANT SELECT, INSERT, DELETE ON storage.objects TO authenticated;
