-- ============================================================
-- FIX: Survey submission via SECURITY DEFINER RPC
-- Run this once in Supabase SQL Editor.
-- ============================================================

create or replace function public.submit_survey_response_public(
  p_survey_id uuid,
  p_user_id uuid,
  p_answers jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_response_id uuid;
  v_item record;
begin
  if p_survey_id is null then
    raise exception 'survey_id is required';
  end if;

  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    raise exception 'answers must be a JSON object';
  end if;

  if not exists (
    select 1
    from public.surveys s
    where s.id = p_survey_id
      and s.is_active = true
  ) then
    raise exception 'Survey is not active or does not exist';
  end if;

  insert into public.survey_responses (survey_id, user_id)
  values (p_survey_id, p_user_id)
  returning id into v_response_id;

  for v_item in
    select key, value
    from jsonb_each(p_answers)
  loop
    insert into public.survey_answers (response_id, question_id, answer_value)
    values (v_response_id, (v_item.key)::uuid, v_item.value);
  end loop;

  return v_response_id;
end;
$$;

grant execute on function public.submit_survey_response_public(uuid, uuid, jsonb)
to anon, authenticated;

