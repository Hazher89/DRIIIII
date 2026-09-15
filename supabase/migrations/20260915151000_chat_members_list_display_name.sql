-- Vis chat_display_name i medlemsliste (behold eksisterende returtype).
CREATE OR REPLACE FUNCTION public.chat_room_members_list(p_room_id UUID)
RETURNS TABLE(
  user_id UUID,
  full_name TEXT,
  member_role TEXT,
  partner_name TEXT,
  account_kind TEXT,
  joined_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    m.user_id,
    public.chat_profile_display_name(p.full_name, p.chat_display_name),
    m.member_role::text,
    coalesce(pt.name, ''),
    CASE
      WHEN public.chat_user_is_mavi_employee(m.user_id) THEN 'mavi'
      WHEN EXISTS (
        SELECT 1 FROM public.partner_portal_accounts ppa
        WHERE ppa.profile_id = m.user_id AND coalesce(ppa.is_active, true)
          AND ppa.account_kind = 'driver'
      ) THEN 'driver'
      WHEN EXISTS (
        SELECT 1 FROM public.partner_portal_accounts ppa
        WHERE ppa.profile_id = m.user_id AND coalesce(ppa.is_active, true)
          AND ppa.account_kind = 'staff'
      ) THEN 'staff'
      ELSE 'owner'
    END,
    m.joined_at
  FROM public.chat_room_members m
  JOIN public.profiles p ON p.id = m.user_id
  LEFT JOIN public.partners pt ON pt.id = m.partner_id
  WHERE m.room_id = p_room_id
    AND m.left_at IS NULL
    AND public.chat_user_can_access_room(auth.uid(), p_room_id)
  ORDER BY m.joined_at ASC;
$$;

GRANT EXECUTE ON FUNCTION public.chat_room_members_list(UUID) TO authenticated;
