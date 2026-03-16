-- ============================================================
-- DRIFTPRO – DMS SETUP (DOKUMENTARKIV)
-- ============================================================

-- 1. Tabeller for mapper og filer
CREATE TABLE IF NOT EXISTS public.dms_folders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    parent_id UUID REFERENCES public.dms_folders(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES public.profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.dms_files (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    folder_id UUID REFERENCES public.dms_folders(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    storage_path TEXT NOT NULL,
    file_size BIGINT,
    extension TEXT,
    created_by UUID NOT NULL REFERENCES public.profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.dms_permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    folder_id UUID REFERENCES public.dms_folders(id) ON DELETE CASCADE,
    file_id UUID REFERENCES public.dms_files(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    permission_type TEXT NOT NULL CHECK (permission_type IN ('read', 'write', 'admin')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT folder_or_file CHECK (
        (folder_id IS NOT NULL AND file_id IS NULL) OR
        (folder_id IS NULL AND file_id IS NOT NULL)
    ),
    UNIQUE (folder_id, user_id),
    UNIQUE (file_id, user_id)
);

-- 2. Aktiver RLS
ALTER TABLE public.dms_folders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dms_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dms_permissions ENABLE ROW LEVEL SECURITY;

-- 3. RLS Policer
DROP POLICY IF EXISTS "DMS Folders Selskap" ON public.dms_folders;
CREATE POLICY "DMS Folders Selskap" ON public.dms_folders FOR ALL 
USING (company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid()));

DROP POLICY IF EXISTS "DMS Files Selskap" ON public.dms_files;
CREATE POLICY "DMS Files Selskap" ON public.dms_files FOR ALL 
USING (company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid()));

DROP POLICY IF EXISTS "DMS Permissions Access" ON public.dms_permissions;
CREATE POLICY "DMS Permissions Access" ON public.dms_permissions FOR ALL 
USING (user_id = auth.uid() OR (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('admin', 'superadmin'));

-- 4. Opprett Storage Bucket (hvis den ikke finnes)
INSERT INTO storage.buckets (id, name, public)
VALUES ('documents', 'documents', false)
ON CONFLICT (id) DO NOTHING;

-- 5. Storage Policer
-- Merk: Disse må ofte settes manuelt i Dashboard eller via spesifikk SQL hvis storage-schema er låst
CREATE POLICY "Document Access" ON storage.objects FOR ALL
USING (bucket_id = 'documents' AND (SELECT count(*) FROM public.profiles WHERE id = auth.uid()) > 0);
