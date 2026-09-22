// controllers/minutes/transcribeFile.js
const { v4: uuidv4 } = require('uuid');
const uploadJson = require('../../../utils/uploadJson');
const {
    successResponse, errorResponse, unauthorizedResponse,
} = require('../../../utils/responseHelper');
const uploadService = require('../../../services/upload.service');
const { summarizeFromTranscript } = require("../../../services/ai.service");
const { convertElevenLabsToSections } = require('../../../utils/convertTranscript');
const { checkUserCanUseCredit, consumeUserCredit } = require('../../../utils/checkAndConsumeUserCredit');
const { upsertMinute } = require('../../../services/minutes.service');

module.exports = async (req, res) => {
    console.log('[transcribeFile] req.file:', req.file);
    // 1️⃣ Accept JSON file
    uploadJson(req, res, async (err) => {
        if (err) {
            console.error('[transcribeFile] Invalid file:', err.message);
            return res.status(400).json(errorResponse(err.message));
        }

        if (!req.user?.user_id) {
            console.warn('[transcribeFile] Missing authenticated user');
            return unauthorizedResponse(res);
        }

        const userId = req.user.user_id;
        const minuteId = uuidv4();

        // 2️⃣ Credit check
        try {
            const check = await checkUserCanUseCredit(userId);
            if (!check.allowed) {
                console.warn(`[transcribeFile] User ${userId} exceeded credits`);
                return res.status(402).json(errorResponse(
                    'You have no credits left. Please upgrade your plan.',
                ));
            }
            console.log(`[transcribeFile] User plan: ${check.plan}, remaining: ${check.credit}`);
        } catch (e) {
            console.error('[transcribeFile] Credit check error:', e.message);
            return res.status(500).json(errorResponse('Failed to check user credit.'));
        }

        // Optional params just like uploadAudio
        const {
            summaryLanguage = 'auto-detect',
            keywords = '',
            description = ''
        } = req.body;

        const timezone = req.headers['X-Timezone'] || req.body.timezone || "GMT -7";

        // 3️⃣ Parse and validate JSON transcript
        let transcriptJson;
        try {
            transcriptJson = JSON.parse(req.file.buffer.toString('utf8'));
            console.log('[transcribeFile] Transcript JSON parsed successfully');
        } catch (e) {
            console.error('[transcribeFile] JSON parsing error:', e.message);
            return res.status(400).json(errorResponse(`Invalid JSON: ${e.message}`));
        }


        // 5️⃣ Convert to section model
        const structuredTranscription = convertElevenLabsToSections(transcriptJson);
        const transcript = JSON.stringify(structuredTranscription, null, 2);

        // 4️⃣ Summarize with OpenAI
        let summaryObj;
        try {
            summaryObj = JSON.parse(await summarizeFromTranscript(
                transcript,
                summaryLanguage,
                description,
                timezone,
            ));
            console.log('[transcribeFile] Summarization completed');
        } catch (e) {
            console.error('[transcribeFile] Summarization error:', e.message);
            return res.status(500).json(errorResponse('Failed to summarize transcript.'));
        }


        // 6️⃣ Upload transcript JSON to GCS
        let transcriptionUri;
        try {
            transcriptionUri = await uploadService.uploadJsonToFolder({
                userId,
                minuteId,
                fileName: 'transcription',
                data: transcriptJson,
                type: 'transcription',
            });
            console.log('[transcribeFile] Transcript JSON uploaded to GCS');
        } catch (e) {
            console.error('[transcribeFile] GCS upload error:', e.message);
            return res.status(500).json(errorResponse('Failed to upload transcript JSON.'));
        }

        // 7️⃣ Save Firestore document & consume credit
        try {
            await upsertMinute(
                userId,
                minuteId,
                structuredTranscription,
                summaryObj,
                {
                    title: summaryObj.title,
                    minuteId,
                    gcsUri: null, // no raw audio file
                    iconAsset: summaryObj.icon,
                    contentType: summaryObj.type,
                    sourceType: "audio",
                    duration: structuredTranscription.duration,
                    transcriptionUri,
                    keywords,
                    descriptionAudio: description,
                    summaryLanguage,
                    createdAt: new Date(),
                },
            );

            await consumeUserCredit(userId);
            console.log('[transcribeFile] Minute stored and credit consumed');
        } catch (e) {
            console.error('[transcribeFile] Firestore save error:', e.message);
            return res.status(500).json(errorResponse('Failed to save minute.'));
        }

        // 8️⃣ Success response
        return successResponse(res, {
            minuteId,
            transcription: structuredTranscription,
            keywords,
            description,
        }, 'Transcript uploaded and processed successfully.');
    });
};