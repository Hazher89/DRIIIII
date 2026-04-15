-- Extend survey question type enum with pro builder types.
do $$
begin
  if exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public'
      and t.typname = 'survey_question_type'
  ) then
    begin
      alter type public.survey_question_type add value if not exists 'single_choice';
      alter type public.survey_question_type add value if not exists 'yes_no';
      alter type public.survey_question_type add value if not exists 'number';
      alter type public.survey_question_type add value if not exists 'email';
      alter type public.survey_question_type add value if not exists 'phone';
      alter type public.survey_question_type add value if not exists 'nps';
    exception
      when duplicate_object then
        null;
    end;
  end if;
end $$;

