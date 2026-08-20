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

export async function createQuestion(quizId, question) {
  if (!getSession()) throw new Error('Connectez-vous en superadmin avant de créer une question.');
  if (!quizId) throw new Error('Choisissez un chapitre disposant d’un quiz.');
  const latest = await request(`questions?quiz_id=eq.${encodeURIComponent(quizId)}&select=position&order=position.desc&limit=1`);
  const position = Number.isInteger(question.position) ? question.position : ((latest?.[0]?.position ?? -1) + 1);

  const created = await request('questions', {
    method: 'POST',
    headers: { Prefer: 'return=representation' },
    body: JSON.stringify({
      quiz_id: quizId,
      body: question.body,
      duration_seconds: question.seconds,
      position,
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

export async function updateQuestion(id, payload) {
  if (!getSession()) throw new Error('Connectez-vous en superadmin avant de modifier une question.');
  await request(`questions?id=eq.${encodeURIComponent(id)}`, {
    method: 'PATCH',
    body: JSON.stringify(payload)
  });
}

export async function updateAnswerOption(id, payload) {
  if (!getSession()) throw new Error('Connectez-vous en superadmin avant de modifier une proposition.');
  await request(`answer_options?id=eq.${encodeURIComponent(id)}`, {
    method: 'PATCH',
    body: JSON.stringify(payload)
  });
}

export async function deleteThemeById(id) {
  if (!getSession()) throw new Error('Connectez-vous en superadmin avant de supprimer un thème.');
  await request(`themes?id=eq.${encodeURIComponent(id)}`, { method: 'DELETE' });
}

export async function deleteChapterById(id) {
  if (!getSession()) throw new Error('Connectez-vous en superadmin avant de supprimer un chapitre.');
  await request(`chapters?id=eq.${encodeURIComponent(id)}`, { method: 'DELETE' });
}

export async function createTheme(name) {
  const normalized = name.trim();
  if (!normalized) throw new Error('Saisissez le nom du thème.');
  const existing = await request(`themes?name=eq.${encodeURIComponent(normalized)}&select=id,name`);
  if (existing?.[0]) return existing[0];
  const latest = await request('themes?select=position&order=position.desc&limit=1');
  const created = await request('themes', {
    method: 'POST', headers: { Prefer: 'return=representation' },
    body: JSON.stringify({ name: normalized, position: (latest?.[0]?.position ?? -1) + 1 })
  });
  if (!created?.[0]) throw new Error('Le thème n’a pas pu être créé.');
  return created[0];
}

export async function createChapterAndQuiz(themeId, title) {
  const normalized = title.trim();
  if (!themeId || !normalized) throw new Error('Saisissez le thème et le chapitre.');
  const latest = await request(`chapters?theme_id=eq.${encodeURIComponent(themeId)}&select=position&order=position.desc&limit=1`);
  const chapters = await request('chapters', {
    method: 'POST', headers: { Prefer: 'return=representation' },
    body: JSON.stringify({ theme_id: themeId, title: normalized, position: (latest?.[0]?.position ?? -1) + 1 })
  });
  const chapter = chapters?.[0];
  if (!chapter) throw new Error('Le chapitre n’a pas pu être créé.');
  const quizzes = await request('quizzes', {
    method: 'POST', headers: { Prefer: 'return=representation' },
    body: JSON.stringify({ chapter_id: chapter.id, title: `Quiz · ${normalized}`, default_duration_seconds: 30 })
  });
  if (!quizzes?.[0]) throw new Error('Le quiz associé au chapitre n’a pas pu être créé.');
  return { chapter, quiz: quizzes[0] };
}

export async function signInAnonymously() {
  const response = await fetch(`${SUPABASE_URL}/auth/v1/signup`, {
    method: 'POST', headers: headers({ 'Content-Type': 'application/json' }), body: JSON.stringify({})
  });
  const payload = await response.json();
  if (!response.ok) {
    if (payload.code === 'anonymous_provider_disabled' || /anonymous sign-ins are disabled/i.test(payload.msg || payload.message || '')) {
      throw new Error('Authentification anonyme désactivée dans Supabase. Activez-la dans Authentication → Providers → Anonymous Sign-Ins.');
    }
    throw new Error(payload.message || payload.error_description || payload.msg || 'Connexion anonyme indisponible.');
  }
  localStorage.setItem(sessionKey, JSON.stringify(payload));
  return payload.user;
}

export async function rpc(name, params = {}) {
  return request(`rpc/${name}`, { method: 'POST', body: JSON.stringify(params) });
}

export async function getInstructorProfile() {
  const session = getSession();
  if (!session?.user?.id) throw new Error('Connexion instructeur requise.');
  const result = await request(`app_users?select=id&auth_user_id=eq.${encodeURIComponent(session.user.id)}`);
  if (!result?.[0]) throw new Error('Profil instructeur introuvable dans app_users.');
  return result[0];
}

export async function getCatalog() {
  return request('themes?select=id,name,chapters(id,title,position,quizzes(id,title,questions(id,body,duration_seconds,position,answer_options(id,label,body,is_correct))))&order=position.asc');
}

export async function createLiveSession(payload) {
  const result = await request('live_sessions', { method: 'POST', headers: { Prefer: 'return=representation' }, body: JSON.stringify(payload) });
  return result?.[0];
}

export async function getLiveSessions() {
  return request('live_sessions?select=id,code,quiz_id,status,current_question_id,question_started_at,question_ends_at,capacity,created_at,session_participants(id,status,user_id,app_users(first_name,last_name)),live_answers(id,question_id,participant_id,option_id)&order=created_at.desc');
}

export async function updateLiveSession(id, payload) {
  await request(`live_sessions?id=eq.${id}`, { method: 'PATCH', body: JSON.stringify(payload) });
}
