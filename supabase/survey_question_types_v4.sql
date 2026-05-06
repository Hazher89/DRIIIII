-- Avanserte spørsmålstyper: likert, slider, time, url
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
      alter type public.survey_question_type add value if not exists 'likert';
      alter type public.survey_question_type add value if not exists 'slider';
      alter type public.survey_question_type add value if not exists 'time';
      alter type public.survey_question_type add value if not exists 'url';
    exception
      when duplicate_object then
        null;
    end;
  end if;
end $$;
