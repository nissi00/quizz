-- Fix the anonymous learner admission function. The output parameter
-- `session_id` conflicted with the column name in the previous UPSERT.
CREATE OR REPLACE FUNCTION public.join_live_by_code(
  p_code text,
  p_first_name text,
  p_last_name text
)
RETURNS TABLE(session_id uuid, participant_id uuid, membership_status participation_status)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.live_sessions%ROWTYPE;
  v_user_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentification apprenant requise';
  END IF;

  SELECT * INTO v_session
  FROM public.live_sessions
  WHERE code = upper(trim(p_code));

  IF NOT FOUND OR v_session.status = 'finished' THEN
    RAISE EXCEPTION 'Session introuvable ou terminée';
  END IF;

  INSERT INTO public.app_users(auth_user_id, first_name, last_name, role)
  VALUES (auth.uid(), trim(p_first_name), trim(p_last_name), 'learner')
  ON CONFLICT (auth_user_id) DO UPDATE
    SET first_name = EXCLUDED.first_name, last_name = EXCLUDED.last_name
  RETURNING id INTO v_user_id;

  INSERT INTO public.session_participants AS sp(session_id, user_id, status)
  VALUES (v_session.id, v_user_id, 'waiting_list')
  ON CONFLICT ON CONSTRAINT session_participants_session_id_user_id_key DO UPDATE
    SET status = sp.status
  RETURNING sp.id, sp.status INTO participant_id, membership_status;

  session_id := v_session.id;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.join_live_by_code(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.join_live_by_code(text, text, text) TO authenticated;
