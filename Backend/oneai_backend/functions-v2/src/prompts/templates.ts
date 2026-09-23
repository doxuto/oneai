import { z } from "zod";

/**
 * Meeting / lecture templates (S11-08). A template does not change the output
 * schema — only the guidance the summariser gets about which sections a
 * reader of that kind of recording expects. "auto" keeps the generic rules.
 */
export const MinuteTemplate = z.enum(["auto", "standup", "one_on_one", "interview", "lecture", "brainstorm"]);
export type MinuteTemplate = z.infer<typeof MinuteTemplate>;

export const TEMPLATE_GUIDANCE: Record<MinuteTemplate, string> = {
  auto: "",
  standup: `This is a daily standup. After the overview, prefer sections "Yesterday", "Today", "Blockers" — inside each, one bullet per person ("Name — …"). Add "Follow-ups" only if someone asked for a discussion outside the standup. Keep it terse.`,
  one_on_one: `This is a 1:1 between a manager and a report. Prefer sections "Wins", "Concerns", "Growth & feedback", "Agreements" (who does what by when), "Next 1:1". Keep sensitive remarks factual; never editorialise.`,
  interview: `This is an interview. Prefer sections "Candidate background", "Questions & answers" (one bullet per question, the answer as a sub-bullet), "Strengths", "Concerns", "Next steps". Only state a recommendation if the interviewer said one.`,
  lecture: `This is a lecture or class. Prefer sections "Learning objectives", "Key concepts" (each with a one-line definition), "Examples", "Open questions", "Review points" (what to revise). Use the lecturer's terminology.`,
  brainstorm: `This is a brainstorm. Prefer sections "Ideas" (grouped by theme, one bullet per idea, who raised it as a sub-bullet if named), "Pros & cons raised", "Decisions & next steps". Do not rank ideas unless the group did.`,
};

export function templateGuidance(t: MinuteTemplate | undefined | null): string {
  const g = TEMPLATE_GUIDANCE[t ?? "auto"] ?? "";
  return g ? `TEMPLATE\n${g}\n` : "";
}
