-- Access scope hardening (GDPR-style least privilege)
-- Employees: own data only
-- Leaders: own + own department
-- Admin/superadmin: all company data

-- -------------------------------
-- TICKETS (AVVIK)
-- -------------------------------
drop policy if exists "Ansatte kan se avvik i sin avdeling" on public.tickets;
drop policy if exists "Ansatte kan opprette avvik" on public.tickets;
drop policy if exists "Ledere kan oppdatere avvik i sin avdeling" on public.tickets;
drop policy if exists "Admin kan se alle avvik i selskapet" on public.tickets;

create policy "tickets_select_scoped"
on public.tickets
for select
using (
  (
    get_user_role() in ('admin', 'superadmin')
    and company_id = get_user_company_id()
  )
  or (
    get_user_role() = 'leder'
    and company_id = get_user_company_id()
    and (department_id = get_user_department_id() or reported_by = auth.uid())
  )
  or (
    get_user_role() = 'ansatt'
    and reported_by = auth.uid()
  )
);

create policy "tickets_insert_scoped"
on public.tickets
for insert
with check (
  company_id = get_user_company_id()
  and reported_by = auth.uid()
);

create policy "tickets_update_scoped"
on public.tickets
for update
using (
  (
    get_user_role() in ('admin', 'superadmin')
    and company_id = get_user_company_id()
  )
  or (
    get_user_role() = 'leder'
    and company_id = get_user_company_id()
    and (department_id = get_user_department_id() or reported_by = auth.uid())
  )
)
with check (
  (
    get_user_role() in ('admin', 'superadmin')
    and company_id = get_user_company_id()
  )
  or (
    get_user_role() = 'leder'
    and company_id = get_user_company_id()
    and (department_id = get_user_department_id() or reported_by = auth.uid())
  )
);

-- -------------------------------
-- ABSENCES (FRAVÆR/FERIE)
-- -------------------------------
drop policy if exists "Ansatte kan se eget fravær" on public.absences;
drop policy if exists "Ledere kan se fravær i sin avdeling" on public.absences;
drop policy if exists "Admin kan se alt fravær i selskapet" on public.absences;
drop policy if exists "Ansatte kan registrere eget fravær" on public.absences;
drop policy if exists "Ledere kan oppdatere fravær i sin avdeling" on public.absences;

create policy "absences_select_scoped"
on public.absences
for select
using (
  (
    get_user_role() in ('admin', 'superadmin')
    and company_id = get_user_company_id()
  )
  or (
    get_user_role() = 'leder'
    and company_id = get_user_company_id()
    and (department_id = get_user_department_id() or user_id = auth.uid())
  )
  or (
    get_user_role() = 'ansatt'
    and user_id = auth.uid()
  )
);

create policy "absences_insert_scoped"
on public.absences
for insert
with check (
  user_id = auth.uid()
  and company_id = get_user_company_id()
);

create policy "absences_update_scoped"
on public.absences
for update
using (
  (
    get_user_role() in ('admin', 'superadmin')
    and company_id = get_user_company_id()
  )
  or (
    get_user_role() = 'leder'
    and company_id = get_user_company_id()
    and (department_id = get_user_department_id() or user_id = auth.uid())
  )
)
with check (
  (
    get_user_role() in ('admin', 'superadmin')
    and company_id = get_user_company_id()
  )
  or (
    get_user_role() = 'leder'
    and company_id = get_user_company_id()
    and (department_id = get_user_department_id() or user_id = auth.uid())
  )
);
