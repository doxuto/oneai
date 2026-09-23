/** Ported from v1's prompt files; the JSON schema enforces structure so the prompts focus on quality. */

export const SHORT_QUESTIONS_PROMPT = `Based on the transcript, write 5 short, clear questions a reader might ask to understand or recall the content. Each question must be answerable from the transcript. Write them in language code '{{languageCode}}'.

Transcript:
'''
{{transcript}}
'''`;

export const QUIZ_PROMPT = `Based on the transcript, write 5 to 10 quiz questions that test understanding. Each question is multiple choice with 2 to 4 options and exactly one correct option (use 2 options for true/false). Options must be plausible and distinct; the correct one must be supported by the transcript. Write everything in language code '{{languageCode}}'.

Transcript:
'''
{{transcript}}
'''`;

export const FLASHCARDS_PROMPT = `Extract 5 to 10 flashcards from the transcript covering its most important ideas or facts. Each card has a clear, concise question and a direct, informative answer that is supported by the transcript. Write everything in language code '{{languageCode}}'.

Transcript:
'''
{{transcript}}
'''`;

export const MINDMAP_PROMPT = `Read the transcript and produce a concise hierarchical mind map of its main topics and sub-topics: root → topic → sub-topic → detail, 2 to 4 levels deep as the content warrants. Node ids are short and unique (n1, n1a, …). The root carries one emoji icon for the subject or tone. Write all titles in language code '{{languageCode}}'.

Transcript:
'''
{{transcript}}
'''`;

export const CALENDAR_EVENTS_PROMPT = `Extract every meeting, deadline, appointment or scheduled event that is clearly stated in the transcript with enough detail to put on a calendar. Rules:
- Only events that are actually planned or agreed — not hypotheticals, past events being recounted, or vague intentions.
- Resolve relative dates ("tomorrow at 3", "next Monday") to absolute ISO-8601 with offset using now and timezone; if the time is unknown, use the date only; if neither can be resolved, put the wording as spoken in datetime.
- title: short, ≤ 10 words. description: one sentence of context. participants: names mentioned as attending (may be empty). rawText: the transcript wording the event came from.
- ids are short and unique (e1, e2, …). No events → an empty list.
Write title and description in language code '{{languageCode}}'.

now: {{now}}   timezone: {{timezone}}

Transcript:
{{transcript}}`;

export const ACTION_ITEMS_PROMPT = `From the transcript, extract (1) action items — concrete things someone committed to do — and (2) decisions that were made. Rules:
- An action item needs a verb and an object ("send the deck to Ana"). No vague intentions, no questions.
- owner: the person named as responsible, exactly as named in the transcript; null when nobody was named.
- due: resolve "by Friday", "next week" to an ISO-8601 date using now and timezone; null when no time was given.
- quote: the transcript words the item came from, verbatim, ≤ 300 characters.
- decisions: one sentence each, only things explicitly agreed. Nothing agreed → empty list.
- ids are short and unique (a1, a2, …). Write text and decisions in language code '{{languageCode}}'; keep names as spoken.

now: {{now}}   timezone: {{timezone}}

Transcript:
'''
{{transcript}}
'''`;

export const KEY_TERMS_PROMPT = `From the transcript, list the technical terms, jargon, acronyms, named concepts and proper nouns a listener might not know. For each: the term as used, a one- or two-sentence definition in the transcript's context (not a dictionary definition), and the verbatim phrase where it first appears. Skip everyday words. 5 to 20 terms, most important first. Write definitions in language code '{{languageCode}}'; keep terms as spoken.

Transcript:
'''
{{transcript}}
'''`;

export const CHAPTERS_PROMPT = `Split this timestamped transcript into chapters by topic, like YouTube chapters. Each line below is "[start-end] speaker: text" in seconds. Rules:
- 3 to 12 chapters for most recordings; a very short one may have 1. Chapters cover the whole recording in order, without overlap: each chapter's startSeconds is a line's start time and endSeconds is the last line's end of that chapter.
- title: ≤ 8 words, specific to what is discussed. summary: one sentence.
- Write titles and summaries in language code '{{languageCode}}'.

Transcript:
{{transcript}}`;

export const MAP_SPEAKERS_SYSTEM = `You map diarised speaker ids (speaker_0, speaker_1, …) to real names, and you never guess.`;

export const MAP_SPEAKERS_PROMPT = `Rules:
1. Assign a name to a speaker id ONLY when the transcript explicitly identifies that speaker. "Thanks, Brian." said by speaker_1 means speaker_1 is talking TO Brian, not that speaker_1 is Brian. "Hi, I'm Brian" or "Brian here" identifies the speaker.
2. If it is not 100 % clear, keep the id as the label (e.g. "speaker_1" → "speaker_1").
3. Output every speaker id that appears in the transcript, exactly once.

Speaker ids present: {{speakerIds}}

Transcript (each line is "speaker_id: text"):
'''
{{transcript}}
'''`;

export const CHAT_SYSTEM = `You answer questions about one transcript. Answer plainly and directly, without preambles like "Based on the transcript". If the answer is not clearly present in the transcript, say only: "I'm not sure based on the transcript." Answer in language code '{{languageCode}}'.`;

export const CHAT_CONTEXT = `Transcript:
'''
{{transcript}}
'''`;

/** S11-04. The input is a chunk of a summary (markdown-ish headings) or a "speaker_N: text" transcript. */
export const TRANSLATE_SYSTEM = `You are a professional translator. Translate the user's text into language code '{{languageCode}}'.
Rules: keep the line structure exactly (one output line per input line, same order); keep prefixes like "speaker_3:", "# ", "## ", "• ", "    ◦ " unchanged; keep proper nouns, product names, code and numbers as they are; do not summarise, add, omit or comment. Output only the translation.`;

