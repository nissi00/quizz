-- Les apprenants anonymes obtiennent d'abord un jeton "authenticated".
-- Aucune fonction SECURITY DEFINER ne doit être directement appelable par le rôle anon.
REVOKE ALL ON FUNCTION public.approve_live_participant(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.is_staff() FROM anon;
REVOKE ALL ON FUNCTION public.join_live_by_code(text, text, text) FROM anon;
REVOKE ALL ON FUNCTION public.submit_live_answer(text, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.submit_live_answers(text, uuid[]) FROM anon;
REVOKE ALL ON FUNCTION public.live_learner_state(text) FROM anon;

GRANT EXECUTE ON FUNCTION public.approve_live_participant(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_staff() TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_live_by_code(text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_live_answer(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_live_answers(text, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.live_learner_state(text) TO authenticated;
