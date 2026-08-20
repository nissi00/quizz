-- Instructors need to read answers from the sessions they manage in order to
-- display individual performances. Learners still cannot read other answers.
DROP POLICY IF EXISTS "staff read live answers" ON public.live_answers;
CREATE POLICY "staff read live answers"
ON public.live_answers
FOR SELECT
TO authenticated
USING (public.is_staff());
