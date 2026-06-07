-- Interne notater for undersøkelser (kun admin, ikke synlig for respondenter).
ALTER TABLE public.surveys
  ADD COLUMN IF NOT EXISTS admin_notes text;

COMMENT ON COLUMN public.surveys.admin_notes IS
  'Interne kommentarer/notater for admin — vises ikke for respondenter.';
