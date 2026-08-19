import { SUPABASE_URL, SUPABASE_ANON_KEY } from './supabase-config.js';

const sessionKey = 'ts-hepa-supabase-session';

function headers(extra = {}) {
  const session = getSession();
  return {
    apikey: SUPABASE_ANON_KEY,
    ...(session ? { Authorization: `Bearer ${session.access_token}` } : {}),
    ...extra
  };
}

export function getSession() {
  try { return JSON.parse(localStorage.getItem(sessionKey) || 'null'); }
  catch { return null; }
}

export async function signIn(email, password) {
  const response = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: headers({ 'Content-Type': 'application/json' }),
    body: JSON.stringify({ email, password })
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error_description || payload.msg || 'Connexion impossible.');
  localStorage.setItem(sessionKey, JSON.stringify(payload));
  return payload.user;
}

export function signOut() { localStorage.removeItem(sessionKey); }

async function request(path, options = {}) {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...options,
    headers: headers({ 'Content-Type': 'application/json', ...(options.headers || {}) })
  });
  const text = await response.text();
  const payload = text ? JSON.parse(text) : null;
  if (!response.ok) throw new Error(payload?.message || payload?.hint || `Erreur Supabase (${response.status}).`);
  return payload;
}

export async function createQuestion(chapterPosition, question) {
  if (!getSession()) throw new Error('Connectez-vous en superadmin avant de créer une question.');
  const chapters = await request('chapters?select=id,title,quizzes(id,title)&order=position.asc');
  const chapter = chapters[chapterPosition];
  // La relation est un objet (un quiz par chapitre), mais PostgREST peut
  // la retourner sous forme de liste selon la configuration de la relation.
  const quiz = Array.isArray(chapter?.quizzes) ? chapter.quizzes[0] : chapter?.quizzes;
  if (!quiz) throw new Error('Quiz introuvable dans Supabase. Vérifiez la migration des données de démonstration.');

  const created = await request('questions', {
    method: 'POST',
    headers: { Prefer: 'return=representation' },
    body: JSON.stringify({
      quiz_id: quiz.id,
      body: question.body,
      duration_seconds: question.seconds,
      position: question.position,
      explanation: question.explanation,
      difficulty: 1,
      subtopic: 'Général'
    })
  });
  const questionId = created?.[0]?.id;
  if (!questionId) throw new Error('La question n’a pas été créée.');
  await request('answer_options', {
    method: 'POST',
    headers: { Prefer: 'return=representation' },
    body: JSON.stringify(question.answers.map((body, index) => ({
      question_id: questionId,
      label: 'ABCD'[index],
      body,
      is_correct: index === question.correct
    })))
  });
  return questionId;
}
