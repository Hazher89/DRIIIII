-- Survey builder v2: sections, conditional logic and response scoring.

alter table public.survey_questions
  add column if not exists section_title text,
  add column if not exists points integer not null default 0,
  add column if not exists condition_question_id uuid references public.survey_questions(id) on delete set null,
  add column if not exists condition_operator text,
  add column if not exists condition_value text;

create table if not exists public.survey_response_scores (
  id uuid primary key default gen_random_uuid(),
  response_id uuid not null unique references public.survey_responses(id) on delete cascade,
  survey_id uuid not null references public.surveys(id) on delete cascade,
  total_score integer not null default 0,
  max_score integer not null default 0,
  answered_count integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.survey_response_scores enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'survey_response_scores'
      and policyname = 'survey_response_scores_rw_company'
  ) then
    create policy survey_response_scores_rw_company on public.survey_response_scores
      for all to authenticated
      using (
        exists (
          select 1
          from public.surveys s
          join public.profiles p on p.company_id = s.company_id
          where s.id = survey_response_scores.survey_id
            and p.id = auth.uid()
        )
      )
      with check (
        exists (
          select 1
          from public.surveys s
          join public.profiles p on p.company_id = s.company_id
          where s.id = survey_response_scores.survey_id
            and p.id = auth.uid()
        )
      );
  end if;
end $$;

