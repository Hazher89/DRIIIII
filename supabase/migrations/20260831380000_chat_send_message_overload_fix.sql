-- PostgREST PGRST203: to send_chat_message-overloads med like standard-parametre.
-- Behold kun 9-param versjonen fra chat_full_advanced.

DROP FUNCTION IF EXISTS public.send_chat_message(uuid, text, uuid, text, jsonb);

GRANT EXECUTE ON FUNCTION public.send_chat_message(
  uuid, text, uuid, text, jsonb, uuid[], uuid, integer, text
) TO authenticated;
