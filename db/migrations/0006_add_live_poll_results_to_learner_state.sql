-- Resultats de sondage anonymes pour la page entre deux questions.
-- Seul un apprenant deja inscrit dans la session peut appeler cette fonction.
CREATE OR REPLACE FUNCTION public.live_learner_state(p_code text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'session_id', ls.id,
    'status', ls.status,
    'participant_status', sp.status,
    'question_started_at', ls.question_started_at,
    'question_ends_at', ls.question_ends_at,
    'question', CASE WHEN ls.current_question_id IS NULL THEN NULL ELSE (
      SELECT jsonb_build_object(
        'id', q.id, 'body', q.body, 'duration_seconds', q.duration_seconds,
        'position', q.position,
        'options', COALESCE((
          SELECT jsonb_agg(jsonb_build_object('id', ao.id, 'label', ao.label, 'body', ao.body) ORDER BY ao.label)
          FROM public.answer_options ao WHERE ao.question_id = q.id
        ), '[]'::jsonb)
      ) FROM public.questions q WHERE q.id = ls.current_question_id
    ) END,
    'poll_results', CASE WHEN ls.current_question_id IS NULL THEN '[]'::jsonb ELSE COALESCE((
      SELECT jsonb_agg(jsonb_build_object('label', options.label, 'response_count', options.response_count) ORDER BY options.label)
      FROM (
        SELECT ao.label, count(la.id)::integer AS response_count
        FROM public.answer_options ao
        LEFT JOIN public.live_answers la ON la.option_id = ao.id AND la.session_id = ls.id AND la.question_id = ls.current_question_id
        WHERE ao.question_id = ls.current_question_id
        GROUP BY ao.label
      ) AS options
    ), '[]'::jsonb) END
  )
  FROM public.live_sessions ls
  JOIN public.session_participants sp ON sp.session_id = ls.id
  JOIN public.app_users u ON u.id = sp.user_id
  WHERE ls.code = upper(trim(p_code)) AND u.auth_user_id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.live_learner_state(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.live_learner_state(text) TO authenticated;
