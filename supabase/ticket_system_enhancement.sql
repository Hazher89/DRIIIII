-- Avvikssystem: utvidede felter + sikring av indekser
-- Kjør i Supabase SQL Editor etter eksisterende schema.

alter table public.tickets
  add column if not exists root_cause text,
  add column if not exists action_plan jsonb not null default '[]'::jsonb,
  add column if not exists internal_notes text;

create index if not exists idx_tickets_company_status
  on public.tickets (company_id, status);

create index if not exists idx_tickets_company_severity
  on public.tickets (company_id, severity);

create index if not exists idx_tickets_due_date
  on public.tickets (due_date)
  where due_date is not null;

-- Lagre bucket for avviksbilder (offentlig lesbar URL via getPublicUrl i klient)
insert into storage.buckets (id, name, public)
values ('tickets', 'tickets', true)
on conflict (id) do nothing;
