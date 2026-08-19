-- PostgreSQL 15+ / Supabase compatible. No Supabase-specific SQL is required.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE user_role AS ENUM ('learner', 'instructor', 'superadmin');
CREATE TYPE session_status AS ENUM ('waiting', 'live', 'polling', 'finished');
CREATE TYPE participation_status AS ENUM ('joined', 'waiting_list', 'left');

CREATE TABLE app_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id uuid UNIQUE, -- optional reference to Supabase Auth / external identity
  email text UNIQUE,
  first_name text NOT NULL,
  last_name text NOT NULL,
  role user_role NOT NULL DEFAULT 'learner',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE themes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL UNIQUE,
  description text, position integer NOT NULL DEFAULT 0, is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE chapters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), theme_id uuid NOT NULL REFERENCES themes(id) ON DELETE CASCADE,
  title text NOT NULL, description text, position integer NOT NULL DEFAULT 0, is_active boolean NOT NULL DEFAULT true,
  UNIQUE(theme_id, position)
);
CREATE TABLE quizzes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), chapter_id uuid NOT NULL UNIQUE REFERENCES chapters(id) ON DELETE CASCADE,
  title text NOT NULL, instructions text, is_final_exam boolean NOT NULL DEFAULT false,
  default_duration_seconds integer NOT NULL DEFAULT 30 CHECK(default_duration_seconds BETWEEN 5 AND 3600),
  is_active boolean NOT NULL DEFAULT true
);
CREATE TABLE questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), quiz_id uuid NOT NULL REFERENCES quizzes(id) ON DELETE CASCADE,
  body text NOT NULL, difficulty smallint NOT NULL DEFAULT 1 CHECK(difficulty BETWEEN 1 AND 3),
  subtopic text, duration_seconds integer NOT NULL DEFAULT 30 CHECK(duration_seconds BETWEEN 5 AND 3600),
  explanation text, position integer NOT NULL DEFAULT 0, is_active boolean NOT NULL DEFAULT true,
  UNIQUE(quiz_id, position)
);
CREATE TABLE answer_options (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), question_id uuid NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
  label char(1) NOT NULL CHECK(label IN ('A','B','C','D')), body text NOT NULL,
  is_correct boolean NOT NULL DEFAULT false, UNIQUE(question_id, label)
);
CREATE UNIQUE INDEX one_correct_answer_per_question ON answer_options(question_id) WHERE is_correct;
CREATE TABLE grading_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL, passing_score numeric(5,2) NOT NULL CHECK(passing_score BETWEEN 0 AND 100),
  max_attempts integer NOT NULL DEFAULT 1 CHECK(max_attempts > 0), rubric_file_name text, is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE live_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), code varchar(8) NOT NULL UNIQUE,
  quiz_id uuid NOT NULL REFERENCES quizzes(id), instructor_id uuid NOT NULL REFERENCES app_users(id),
  status session_status NOT NULL DEFAULT 'waiting', current_question_id uuid REFERENCES questions(id),
  question_started_at timestamptz, question_ends_at timestamptz, capacity smallint NOT NULL DEFAULT 30 CHECK(capacity BETWEEN 1 AND 30),
  created_at timestamptz NOT NULL DEFAULT now(), ended_at timestamptz
);
CREATE TABLE session_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), session_id uuid NOT NULL REFERENCES live_sessions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES app_users(id), status participation_status NOT NULL DEFAULT 'joined', joined_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(session_id,user_id)
);
CREATE TABLE live_answers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), session_id uuid NOT NULL REFERENCES live_sessions(id) ON DELETE CASCADE,
  question_id uuid NOT NULL REFERENCES questions(id), participant_id uuid NOT NULL REFERENCES session_participants(id) ON DELETE CASCADE,
  option_id uuid NOT NULL REFERENCES answer_options(id), submitted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(session_id, question_id, participant_id)
);
CREATE TABLE quiz_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), quiz_id uuid NOT NULL REFERENCES quizzes(id), user_id uuid NOT NULL REFERENCES app_users(id),
  score numeric(5,2), passed boolean, started_at timestamptz NOT NULL DEFAULT now(), completed_at timestamptz
);

-- Call this inside a transaction when a learner joins. It atomically applies the 30-person limit.
CREATE OR REPLACE FUNCTION join_live_session(p_session_id uuid, p_user_id uuid)
RETURNS participation_status LANGUAGE plpgsql AS $$
DECLARE v_capacity smallint; v_current integer; v_status participation_status;
BEGIN
  SELECT capacity INTO v_capacity FROM live_sessions WHERE id=p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Session inconnue'; END IF;
  SELECT count(*) INTO v_current FROM session_participants WHERE session_id=p_session_id AND status='joined';
  v_status := CASE WHEN v_current < v_capacity THEN 'joined' ELSE 'waiting_list' END;
  INSERT INTO session_participants(session_Diagnostic

Connexion Supabase
✓ Connexion Supabase réussie.
URL et clé publique valides. Vous pouvez maintenant exécuter les migrations SQL.

Ce test ne crée ni ne modifie de table.

Relancer le testid,user_id,status) VALUES(p_session_id,p_user_id,v_status)
  ON CONFLICT(session_id,user_id) DO UPDATE SET status=EXCLUDED.status;
  RETURN v_status;
END $$;

-- Create public views that deliberately do not expose correct answers to learners.
CREATE VIEW learner_questions AS
SELECT q.id, q.quiz_id, q.body, q.difficulty, q.subtopic, q.duration_seconds, q.position,
       jsonb_agg(jsonb_build_object('id',o.id,'label',o.label,'body',o.body) ORDER BY o.label) AS options
FROM questions q JOIN answer_options o ON o.question_id=q.id
WHERE q.is_active GROUP BY q.id;
CREATE VIEW live_poll_results AS
SELECT la.session_id, la.question_id, ao.label, count(*) AS response_count
FROM live_answers la JOIN answer_options ao ON ao.id=la.option_id
GROUP BY la.session_id, la.question_id, ao.label;
