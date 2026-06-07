-- Alle filstørrelser til Dropbox når koblet (0 = ingen Supabase-grense på størrelse).
update public.company_dropbox_connections
set large_file_threshold_bytes = 0,
    updated_at = now()
where large_file_threshold_bytes is distinct from 0;

alter table public.company_dropbox_connections
  alter column large_file_threshold_bytes set default 0;

comment on column public.company_dropbox_connections.large_file_threshold_bytes is
  'Filer under denne størrelsen kan lagres i Supabase. 0 = alltid Dropbox når koblet og modul er på.';

-- SAP innboks-modul for eksisterende tilkoblinger
update public.company_dropbox_connections
set storage_modules = coalesce(storage_modules, '{}'::jsonb) || '{"sap_inbox": true}'::jsonb,
    updated_at = now()
where not coalesce(storage_modules, '{}'::jsonb) ? 'sap_inbox';
