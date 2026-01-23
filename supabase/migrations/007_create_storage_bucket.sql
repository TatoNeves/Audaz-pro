-- ============================================
-- AUDAZ PRO - CREATE STORAGE BUCKET
-- Migration 007: Create ticket-attachments bucket
--
-- Execute this in Supabase Dashboard > SQL Editor
-- ============================================

-- Step 1: Create the bucket if it doesn't exist
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'ticket-attachments',
    'ticket-attachments',
    true,  -- Public bucket (allows getPublicUrl to work)
    10485760,  -- 10MB file size limit
    ARRAY[
        'image/jpeg',
        'image/png',
        'image/gif',
        'image/webp',
        'image/svg+xml',
        'video/mp4',
        'video/webm',
        'video/quicktime',
        'application/pdf',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.ms-excel',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/vnd.ms-powerpoint',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'text/plain',
        'application/zip',
        'application/x-rar-compressed'
    ]::text[]
)
ON CONFLICT (id) DO UPDATE SET
    public = true,
    file_size_limit = 10485760;

-- Step 2: Enable RLS on storage.objects (if not already enabled)
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Step 3: Drop existing policies to avoid conflicts
DROP POLICY IF EXISTS "Allow authenticated users to upload ticket attachments" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated users to read ticket attachments" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated users to delete ticket attachments" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated ticket attachments upload" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated ticket attachments read" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated ticket attachments delete" ON storage.objects;

-- Step 4: Create INSERT policy - Allow authenticated users to upload
CREATE POLICY "Allow authenticated users to upload ticket attachments"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'ticket-attachments'
);

-- Step 5: Create SELECT policy - Allow authenticated users to read/download
CREATE POLICY "Allow authenticated users to read ticket attachments"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'ticket-attachments'
);

-- Step 6: Create UPDATE policy - Allow authenticated users to update their files
CREATE POLICY "Allow authenticated users to update ticket attachments"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
    bucket_id = 'ticket-attachments'
)
WITH CHECK (
    bucket_id = 'ticket-attachments'
);

-- Step 7: Create DELETE policy - Allow authenticated users to delete
CREATE POLICY "Allow authenticated users to delete ticket attachments"
ON storage.objects
FOR DELETE
TO authenticated
USING (
    bucket_id = 'ticket-attachments'
);

-- Step 8: Grant permissions (belt and suspenders)
GRANT ALL ON storage.objects TO authenticated;
GRANT ALL ON storage.buckets TO authenticated;

-- Verify bucket was created
SELECT id, name, public, file_size_limit FROM storage.buckets WHERE id = 'ticket-attachments';
