-- Vision monitor events: person entry / PPE / parking with Dropbox snapshot URL.

create table if not exists public.vision_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  camera_id text not null,
  event_type text not null check (
    event_type in ('ppe_violation', 'parking_entry', 'parking_exit')
  ),
  status text not null default 'open' check (
    status in ('open', 'acknowledged', 'resolved', 'dismissed')
  ),
  dropbox_image_url text not null,
  dropbox_path text not null,
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists vision_events_company_occurred_idx
  on public.vision_events (company_id, occurred_at desc);

create index if not exists vision_events_camera_idx
  on public.vision_events (camera_id, occurred_at desc);

comment on table public.vision_events is
  'Camera vision incidents with Dropbox-hosted snapshot URLs for the web platform.';

alter table public.vision_events enable row level security;

drop policy if exists vision_events_select_company on public.vision_events;

-- Company members can read their events.
create policy vision_events_select_company
  on public.vision_events
  for select
  to authenticated
  using (
    company_id = (
      select company_id from public.profiles where id = auth.uid()
    )
  );

-- Edge service uses service role (bypasses RLS). No insert policy for authenticated clients.

grant select on public.vision_events to authenticated;
grant all on public.vision_events to service_role;
