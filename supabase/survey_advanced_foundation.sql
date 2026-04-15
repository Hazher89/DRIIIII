-- Advanced survey foundation: theming, archive and analytics snapshots.

create table if not exists public.survey_theme_configs (
  survey_id uuid primary key references public.surveys(id) on delete cascade,
  primary_hex text not null default '#1B5E20',
  background_hex text not null default '#F7F9F8',
  card_hex text not null default '#FFFFFF',
  text_hex text not null default '#0F172A',
  accent_hex text not null default '#0D47A1',
  logo_url text,
  font_family text not null default 'Inter',
  button_style text not null default 'rounded',
  dark_mode_for_respondent boolean not null default false,
  compact_mode boolean not null default false,
  show_progress_bar boolean not null default true,
  show_estimated_time boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.survey_archive_entries (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.surveys(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  title text not null,
  status text not null default 'archived',
  archived_by uuid not null references auth.users(id) on delete cascade,
  archived_at timestamptz not null default now(),
  responses_at_archive integer not null default 0,
  note text
);

create table if not exists public.survey_analytics_snapshots (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.surveys(id) on delete cascade,
  total_responses integer not null default 0,
  completed_responses integer not null default 0,
  completion_rate numeric(5,2) not null default 0,
  average_duration_sec numeric(10,2) not null default 0,
  drop_off_count integer not null default 0,
  sentiment_score numeric(4,2) not null default 0,
  top_themes jsonb not null default '{}'::jsonb,
  generated_at timestamptz not null default now()
);

alter table public.survey_theme_configs enable row level security;
alter table public.survey_archive_entries enable row level security;
alter table public.survey_analytics_snapshots enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'survey_theme_configs'
      and policyname = 'survey_theme_configs_rw_company'
  ) then
    create policy survey_theme_configs_rw_company on public.survey_theme_configs
      for all to authenticated
      using (
        exists (
          select 1
          from public.surveys s
          join public.profiles p on p.company_id = s.company_id
          where s.id = survey_theme_configs.survey_id
            and p.id = auth.uid()
        )
      )
      with check (
        exists (
          select 1
          from public.surveys s
          join public.profiles p on p.company_id = s.company_id
          where s.id = survey_theme_configs.survey_id
            and p.id = auth.uid()
        )
      );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'survey_archive_entries'
      and policyname = 'survey_archive_entries_rw_company'
  ) then
    create policy survey_archive_entries_rw_company on public.survey_archive_entries
      for all to authenticated
      using (
        exists (
          select 1
          from public.profiles p
          where p.company_id = survey_archive_entries.company_id
            and p.id = auth.uid()
        )
      )
      with check (
        exists (
          select 1
          from public.profiles p
          where p.company_id = survey_archive_entries.company_id
            and p.id = auth.uid()
        )
      );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'survey_analytics_snapshots'
      and policyname = 'survey_analytics_snapshots_read_company'
  ) then
    create policy survey_analytics_snapshots_read_company on public.survey_analytics_snapshots
      for select to authenticated
      using (
        exists (
          select 1
          from public.surveys s
          join public.profiles p on p.company_id = s.company_id
          where s.id = survey_analytics_snapshots.survey_id
            and p.id = auth.uid()
        )
      );
  end if;
end $$;

