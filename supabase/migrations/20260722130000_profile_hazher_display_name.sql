-- Visningsnavn for superadmin-eier: Hazher (ikke e-postprefix / OAuth-navn).

UPDATE public.profiles
SET full_name = 'Hazher'
WHERE lower(email) IN (
  'baxigshti@gmail.com',
  'baxightsi@gmail.com',
  'baxigshti@hotmail.de',
  'baxlgshtl@gmail.com',
  'hazher@mavilogistikk.no'
)
AND coalesce(trim(full_name), '') <> 'Hazher';

UPDATE auth.users u
SET raw_user_meta_data = coalesce(u.raw_user_meta_data, '{}'::jsonb)
  || jsonb_build_object('full_name', 'Hazher', 'name', 'Hazher')
WHERE lower(coalesce(u.email, '')) IN (
  'baxigshti@gmail.com',
  'baxightsi@gmail.com',
  'baxigshti@hotmail.de',
  'baxlgshtl@gmail.com',
  'hazher@mavilogistikk.no'
);
