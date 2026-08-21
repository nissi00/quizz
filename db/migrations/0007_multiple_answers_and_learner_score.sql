-- Une question peut avoir une ou plusieurs bonnes propositions.
DROP INDEX IF EXISTS public.one_correct_answer_per_question;

-- Une ligne de live_answers devient une sélection. La soumission conserve
-- l'unicité d'une réponse complète par apprenant et par question.
ALTER TABLE public.live_answers
  DROP CONSTRAINT IF EXISTS live_answers_session_id_question_id_participant_id_key;
ALTER TABLE public.live_answers
  ADD CONSTRAINT live_answers_one_selection_per_option
  UNIQUE (session_id, question_id, participant_id, option_id);

CREATE TABLE IF NOT EXISTS public.live_answer_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES public.live_sessions(id) ON DELETE CASCADE,
  question_id uuid NOT NULL REFERENCES public.questions(id),
  participant_id uuid NOT NULL REFERENCES public.session_participants(id) ON DELETE CASCADE,
  is_correct boolean NOT NULL,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (session_id, question_id, participant_id)
);

CREATE INDEX IF NOT EXISTS live_answer_submissions_session_participant_idx
  ON public.live_answer_submissions(session_id, participant_id);

-- Conservation des anciennes réponses déjà enregistrées.
INSERT INTO public.live_answer_submissions(session_id, question_id, participant_id, is_correct, submitted_at)
SELECT la.session_id, la.question_id, la.participant_id, ao.is_correct, la.submitted_at
FROM public.live_answers la
JOIN public.answer_options ao ON ao.id = la.option_id
ON CONFLICT (session_id, question_id, participant_id) DO NOTHING;

ALTER TABLE public.live_answer_submissions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "staff read answer submissions"
ON public.live_answer_submissions FOR SELECT TO authenticated
USING (public.is_staff());

CREATE OR REPLACE FUNCTION public.submit_live_answers(p_code text, p_option_ids uuid[])
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session_id uuid;
  v_question_id uuid;
  v_participant_id uuid;
  v_correct_ids uuid[];
  v_is_correct boolean;
BEGIN
  SELECT ls.id, ls.current_question_id, sp.id
  INTO v_session_id, v_question_id, v_participant_id
  FROM public.live_sessions ls
  JOIN public.session_participants sp ON sp.session_id = ls.id
  JOIN public.app_users u ON u.id = sp.user_id
  WHERE ls.code = upper(trim(p_code))
    AND u.auth_user_id = auth.uid()
    AND sp.status = 'joined'
    AND ls.status = 'live'
    AND ls.question_ends_at > now();

  IF NOT FOUND THEN RAISE EXCEPTION 'Réponse non autorisée'; END IF;
  IF p_option_ids IS NULL OR cardinality(p_option_ids) = 0 THEN
    RAISE EXCEPTION 'Choisissez au moins une proposition';
  END IF;
  IF cardinality(p_option_ids) <> cardinality(ARRAY(SELECT DISTINCT selected.option_id FROM unnest(p_option_ids) AS selected(option_id))) THEN
    RAISE EXCEPTION 'Propositions dupliquées';
  END IF;
  IF (SELECT count(*) FROM public.answer_options WHERE question_id = v_question_id AND id = ANY(p_option_ids)) <> cardinality(p_option_ids) THEN
    RAISE EXCEPTION 'Proposition invalide';
  END IF;

  SELECT array_agg(id ORDER BY id) INTO v_correct_ids
  FROM public.answer_options
  WHERE question_id = v_question_id AND is_correct;

  SELECT array_agg(selected.option_id ORDER BY selected.option_id) = v_correct_ids INTO v_is_correct
  FROM unnest(p_option_ids) AS selected(option_id);

  INSERT INTO public.live_answer_submissions(session_id, question_id, participant_id, is_correct)
  VALUES (v_session_id, v_question_id, v_participant_id, COALESCE(v_is_correct, false))
  ON CONFLICT (session_id, question_id, participant_id) DO NOTHING;

  IF FOUND THEN
    INSERT INTO public.live_answers(session_id, question_id, participant_id, option_id)
    SELECT v_session_id, v_question_id, v_participant_id, selected.option_id
    FROM unnest(p_option_ids) AS selected(option_id);
  END IF;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_live_answers(text, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_live_answers(text, uuid[]) TO authenticated;

-- Compatibilité temporaire avec les clients plus anciens à réponse unique.
CREATE OR REPLACE FUNCTION public.submit_live_answer(p_code text, p_option_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT public.submit_live_answers(p_code, ARRAY[p_option_id]);
$$;

REVOKE ALL ON FUNCTION public.submit_live_answer(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_live_answer(text, uuid) TO authenticated;

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
    'question_expired', COALESCE(ls.question_ends_at <= now(), false),
    'question', CASE WHEN ls.current_question_id IS NULL THEN NULL ELSE (
      SELECT jsonb_build_object(
        'id', q.id, 'body', q.body, 'duration_seconds', q.duration_seconds,
        'position', q.position,
        'multiple_answers', (SELECT count(*) > 1 FROM public.answer_options ao WHERE ao.question_id = q.id AND ao.is_correct),
        'options', COALESCE((
          SELECT jsonb_agg(jsonb_build_object('id', ao.id, 'label', ao.label, 'body', ao.body) ORDER BY ao.label)
          FROM public.answer_options ao WHERE ao.question_id = q.id
        ), '[]'::jsonb)
      ) FROM public.questions q WHERE q.id = ls.current_question_id
    ) END,
    'answer_result', CASE
      WHEN ls.current_question_id IS NOT NULL AND (ls.status = 'polling' OR ls.question_ends_at <= now())
      THEN COALESCE((
        SELECT las.is_correct FROM public.live_answer_submissions las
        WHERE las.session_id = ls.id AND las.question_id = ls.current_question_id AND las.participant_id = sp.id
      ), false)
      ELSE NULL
    END,
    'final_score', CASE WHEN ls.status = 'finished' THEN (
      SELECT jsonb_build_object(
        'correct_answers', count(*) FILTER (WHERE las.is_correct),
        'question_count', (SELECT count(*) FROM public.questions q WHERE q.quiz_id = ls.quiz_id),
        'percent', CASE WHEN (SELECT count(*) FROM public.questions q WHERE q.quiz_id = ls.quiz_id) = 0 THEN 0
          ELSE round(100.0 * count(*) FILTER (WHERE las.is_correct) / (SELECT count(*) FROM public.questions q WHERE q.quiz_id = ls.quiz_id))
        END
      )
      FROM public.live_answer_submissions las WHERE las.session_id = ls.id AND las.participant_id = sp.id
    ) ELSE NULL END,
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
