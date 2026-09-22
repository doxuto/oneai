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
