/**
 * setGlobalOptions MUST be the first statement — ES imports are hoisted, so
 * it runs before any function definition is evaluated.
 * This file contains setGlobalOptions plus explicit re-exports and nothing else.
 */
import { setGlobalOptions } from "firebase-functions/v2";

setGlobalOptions({
  region: "asia-southeast1",
  maxInstances: 20,
  memory: "512MiB",
  timeoutSeconds: 60,
});

export { getMe } from "./users/getMe.js";
export { onUserCreated } from "./users/onUserCreated.js";
export { onUserDeleted } from "./users/onUserDeleted.js";

export { createMinute } from "./minutes/createMinute.js";
export { listMinutes } from "./minutes/listMinutes.js";
export { getMinute } from "./minutes/getMinute.js";
export { updateMinute } from "./minutes/updateMinute.js";
export { deleteMinute } from "./minutes/deleteMinute.js";
export { onMinuteWritten } from "./minutes/onMinuteWritten.js";

export { createTag } from "./tags/createTag.js";
export { listTags } from "./tags/listTags.js";
export { updateTag } from "./tags/updateTag.js";
export { deleteTag } from "./tags/deleteTag.js";

export { startTranscription } from "./transcribe/startTranscription.js";
export { cancelTranscription } from "./transcribe/cancelTranscription.js";
export { processTranscription } from "./transcribe/processTranscription.js";

export { sweepOrphanFiles } from "./jobs/sweepOrphanFiles.js";

export { chat } from "./ai/chat.js";
export { listChatMessages } from "./ai/listChatMessages.js";
export { generateShortQuestions } from "./ai/generateShortQuestions.js";
export { generateQuiz } from "./ai/generateQuiz.js";
export { generateFlashcards } from "./ai/generateFlashcards.js";
export { generateMindmap } from "./ai/generateMindmap.js";
export { mapSpeakers } from "./ai/mapSpeakers.js";
export { renameSpeaker } from "./ai/renameSpeaker.js";

export { revenueCatWebhook } from "./billing/revenueCatWebhook.js";
export { adRewardSsv } from "./ads/adRewardSsv.js";
