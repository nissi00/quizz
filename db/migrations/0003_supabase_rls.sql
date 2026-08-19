-- À exécuter après 0001_initial.sql sur Supabase.
-- L'API doit associer app_users.auth_user_id à auth.uid() lors de la connexion.

ALTER TABLE app_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE themes ENABLE ROW LEVEL SECURITY;
ALTER TABLE chapters ENABLE ROW LEVEL SECURITY;
ALTER TABLE quizzes ENABLE ROW LEVEL SECURITY;
ALTER TABLE questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE answer_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE live_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE live_answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE quiz_attempts ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION is_staff()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM app_users
    WHERE auth_user_id = auth.uid() AND role IN ('instructor', 'superadmin')
  );
$$;

CREATE POLICY "staff manage themes" ON themes FOR ALL USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "staff manage chapters" ON chapters FOR ALL USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "staff manage quizzes" ON quizzes FOR ALL USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "staff manage questions" ON questions FOR ALL USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "staff manage options" ON answer_options FOR ALL USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "staff manage sessions" ON live_sessions FOR ALL USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY "users read own profile" ON app_users FOR SELECT USING (auth_user_id = auth.uid() OR is_staff());
CREATE POLICY "users update own profile" ON app_users FOR UPDATE USING (auth_user_id = auth.uid());
CREATE POLICY "participants see joined session" ON session_participants FOR SELECT USING (user_id IN (SELECT id FROM app_users WHERE auth_user_id = auth.uid()) OR is_staff());
CREATE POLICY "participants join own session" ON session_participants FOR INSERT WITH CHECK (user_id IN (SELECT id FROM app_users WHERE auth_user_id = auth.uid()));
CREATE POLICY "participants answer once" ON live_answers FOR INSERT WITH CHECK (
  participant_id IN (SELECT sp.id FROM session_participants sp JOIN app_users u ON u.id=sp.user_id WHERE u.auth_user_id=auth.uid())
);
CREATE POLICY "own attempts" ON quiz_attempts FOR ALL USING (user_id IN (SELECT id FROM app_users WHERE auth_user_id = auth.uid()) OR is_staff());

-- Ne donnez pas SELECT sur answer_options directement aux apprenants :
-- ils doivent lire la vue learner_questions, qui ne contient jamais is_correct.
GRANT SELECT ON learner_questions TO authenticated;
GRANT SELECT ON live_poll_results TO authenticated;
