-- Kjør i Supabase SQL Editor: sett visningsnavn Hazher for baxigshti@gmail.com m.fl.
-- Deretter: logg ut og inn igjen i appen.

UPDATE public.profiles
SET full_name = 'Hazher'
WHERE lower(email) IN (
  'baxigshti@gmail.com',
  'baxightsi@gmail.com',
  'baxigshti@hotmail.de',
  'baxlgshtl@gmail.com',
  'hazher@mavilogistikk.no'
);

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

SELECT id, email, full_name, role FROM public.profiles
WHERE lower(email) IN (
  'baxigshti@gmail.com',
  'baxightsi@gmail.com',
  'baxigshti@hotmail.de',
  'baxlgshtl@gmail.com',
  'hazher@mavilogistikk.no'
);
