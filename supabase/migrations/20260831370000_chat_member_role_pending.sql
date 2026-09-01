-- Fix: chat_member_role manglet 'pending' og 'admin' som brukes i 20260831360000.
-- Uten disse feiler send_chat_message med: invalid input value for enum chat_member_role: "pending"

ALTER TYPE public.chat_member_role ADD VALUE IF NOT EXISTS 'admin';
ALTER TYPE public.chat_member_role ADD VALUE IF NOT EXISTS 'pending';

-- Rett trigger: member_role er NOT NULL DEFAULT 'member', aldri NULL ved insert
CREATE OR REPLACE FUNCTION public.chat_on_member_joined()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_welcome TEXT; v_room public.chat_rooms%ROWTYPE;
BEGIN
  IF NEW.left_at IS NOT NULL THEN RETURN NEW; END IF;
  SELECT * INTO v_room FROM public.chat_rooms WHERE id = NEW.room_id;
  v_welcome := nullif(trim(v_room.welcome_message), '');
  IF v_welcome IS NOT NULL THEN
    INSERT INTO public.chat_messages (room_id, sender_id, body, message_type)
    VALUES (NEW.room_id, coalesce(v_room.created_by, NEW.user_id), v_welcome, 'system');
  END IF;
  IF v_room.require_member_approval
     AND NEW.member_role = 'member'::public.chat_member_role
     AND NEW.user_id IS DISTINCT FROM v_room.created_by THEN
    NEW.member_role := 'pending'::public.chat_member_role;
  END IF;
  RETURN NEW;
END;
$$;
