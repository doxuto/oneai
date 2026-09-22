const { uploadAudio } = require('../../../utils/uploadAudio');
const { v4: uuidv4 } = require('uuid');
const { successResponse, errorResponse, unauthorizedResponse } = require("../../../utils/responseHelper");
const FormData = require('form-data');
const { summarizeFromTranscript } = require("../../../services/ai.service");
const uploadService = require('../../../services/upload.service');
const { db } = require("../../../config/config-firebase");
const { convertElevenLabsToSections } = require('../../../utils/convertTranscript');
const { checkUserCanUseCredit, consumeUserCredit } = require("../../../utils/checkAndConsumeUserCredit");
const { getAudioDurationFromBuffer } = require("../../../utils/getAudioDuration");
const { upsertMinute } = require('../../../services/minutes.service');

module.exports = async (req, res) => {
    const axios = require('axios');
    uploadAudio(req, res, async function (err) {
        console.log("🚀 [uploadAudio] Starting process...");

        console.log("👉 req.user:", req.user);
        console.log("👉 req.file:", req.file);
        console.log("👉 req.body:", req.body);

        const userId = req.user.user_id;

        if (!req.user?.user_id) {
            console.warn("⚠️ [uploadAudio] Missing authenticated user.");
            return unauthorizedResponse(res);
        }
        var check = null;
        try {
            check = await checkUserCanUseCredit(userId);
            if (!check.allowed) {
                console.warn(`⛔ User ${userId} exceeded credit limit.`);
                return res.status(402).json(errorResponse("You have no credits left. Please upgrade your plan."));
            }
            console.log(`✅ User authorized with plan: ${check.plan}, remaining credit: ${check.credit}`);
        } catch (err) {
            console.error("❌ Credit check error:", err.message);
            return res.status(500).json(errorResponse("Failed to check user credit."));
        }

        try {
            const durationInSeconds = await getAudioDurationFromBuffer(req.file.buffer);
            const mins = Math.floor(durationInSeconds / 60);
            const secs = Math.round(durationInSeconds % 60);
            console.log(`🕒 [Duration Check] Audio length: ${mins}m ${secs}s`);

            if (check.plan === 'free' && durationInSeconds > 1800) {
                console.warn(`⛔ User ${userId} on FREE plan tried to upload audio > 30 mins`);
                return res.status(403).json(errorResponse("Free plan supports audio up to 30 minutes only. Please upgrade your plan."));
            }
        } catch (err) {
            console.error("❌ Failed to get audio duration:", err);
            return res.status(500).json(errorResponse("Unable to process audio file."));
        }

        const {
            audioLanguage = "auto-detect",
            summaryLanguage = "auto-detect",
            keywords = "",
            description = "",
        } = req.body;

        const timezone = req.headers['X-Timezone'] || req.body.timezone || "GMT -7";
        console.log(`✅ [uploadAudio] Params: audioLanguage=${audioLanguage}, summaryLanguage=${summaryLanguage}, keywords=${keywords}, description=${description}, timezone=${timezone}`);

        const minuteId = uuidv4();
        const filename = uuidv4();
        // ✅ Add this helper in your file or utilities
        const languageMap = {
            afr: 'afr', amh: 'amh', ara: 'ara', asm: 'asm', aze: 'aze', bak: 'bak',
            bel: 'bel', bul: 'bul', ben: 'ben', bod: 'bod', bos: 'bos', cat: 'cat',
            ceb: 'ceb', ces: 'ces', chv: 'chv', cym: 'cym', dan: 'dan', deu: 'deu',
            div: 'div', ell: 'ell', eng: 'eng', epo: 'epo', spa: 'spa', est: 'est',
            eus: 'eus', fas: 'fas', fin: 'fin', fil: 'fil', fra: 'fra', fry: 'fry',
            gle: 'gle', glg: 'glg', guj: 'guj', hau: 'hau', heb: 'heb', hin: 'hin',
            hrv: 'hrv', hun: 'hun', hye: 'hye', ind: 'ind', isl: 'isl', ita: 'ita',
            jpn: 'jpn', jav: 'jav', kat: 'kat', kaz: 'kaz', khm: 'khm', kan: 'kan',
            kor: 'kor', kur: 'kur', kir: 'kir', lao: 'lao', lit: 'lit', lav: 'lav',
            mkd: 'mkd', mal: 'mal', mon: 'mon', mar: 'mar', msa: 'msa', mya: 'mya',
            nep: 'nep', nld: 'nld', nor: 'nor', pan: 'pan', pol: 'pol', pus: 'pus',
            por: 'por', ron: 'ron', rus: 'rus', san: 'san', snd: 'snd', sin: 'sin',
            slk: 'slk', slv: 'slv', som: 'som', sqi: 'sqi', srp: 'srp', sun: 'sun',
            swe: 'swe', swa: 'swa', tam: 'tam', tel: 'tel', tha: 'tha', tur: 'tur',
            ukr: 'ukr', urd: 'urd', uzb: 'uzb', vie: 'vie', zho: 'zho', zul: 'zul'
        };

        // ✅ Get base language code ('en-US' → 'en')
        const mapLanguageCode = (input) => {
            if (!input) return null;
            const base = input.split('-')[0].toLowerCase();
            return languageMap[base] ?? null;
        };

        const mappedLang = mapLanguageCode(audioLanguage);

        try {
            // ✅ Prepare FormData for ElevenLabs API
            const form = new FormData();
            form.append('model_id', 'scribe_v1');
            form.append('file', req.file.buffer, {
                filename: req.file.originalname,
                contentType: req.file.mimetype || 'audio/mpeg'
            });
            form.append('diarize', 'true');
            form.append('tag_audio_events', 'true');
            if (mappedLang) {
                form.append('language_code', mappedLang);
                console.log(`✅ [uploadAudio] Using mapped language: ${mappedLang}`);
            } else {
                console.log(`⚠️ [uploadAudio] Language not mapped, auto-detect enabled.`);
            }

            console.log("📤 [uploadAudio] Sending file to ElevenLabs via axios...");
            const response = await axios.post('https://api.elevenlabs.io/v1/speech-to-text', form, {
                headers: {
                    ...form.getHeaders(),
                    'xi-api-key': process.env.ELEVENLABS_API_KEY
                },
                maxContentLength: Infinity,
                maxBodyLength: Infinity,
                timeout: 300000   // ✅ optional: increase timeout (5 mins)
            });

            console.log("✅ [uploadAudio] ElevenLabs transcription completed");

            // ✅ Step 1: Upload file to GCS
            console.log("📤 [uploadAudio] Uploading file to Google Cloud Storage...");
            const uploadResult = await uploadService.uploadFileToFolder({
                userId,
                minuteId,
                file: req.file.buffer,
                fileName: filename,
                contentType: req.file.mimetype || 'audio/mpeg'
            });
            console.log("✅ [uploadAudio] File uploaded to GCS.");
            console.log("👉 [uploadAudio] Upload result:", uploadResult);
            let gcsUri = uploadResult.gcsUri;
            const structuredTranscription = convertElevenLabsToSections(response.data);
            const transcript = JSON.stringify(structuredTranscription, null, 2);

            console.log("📝 Starting text summarization with OpenAI...");
            let result;
            try {
                result = JSON.parse(await summarizeFromTranscript(transcript, summaryLanguage, description, timezone));
            } catch (err) {
                console.error("❌ Failed to parse summary JSON:", err);
                return res.status(500).json(errorResponse("Failed to summarize audio content."));
            }

            const { title, summaryText, icon, type } = result || {};
            console.log("✅ Summarization completed.");
            console.log("👉 Summary:", summaryText);
            console.log(`✅ File read successfully. Saving transcript json to Firestore users/${userId}/minutes/${minuteId}`);


            const transcriptionUri = await uploadService.uploadJsonToFolder({
                userId,
                fileName: 'transcription',
                data: response.data,
                minuteId,
                type: 'transcription'
            });

            // const summaryUri = await uploadService.uploadJsonToFolder({
            //     userId,
            //     fileName: 'summary',
            //     data: result,
            //     minuteId,
            //     type: 'summary'
            // });

            // 👉 Save full JSON object as transcript
            await upsertMinute(userId, minuteId, structuredTranscription, result, {
                title,
                minuteId,
                gcsUri,
                iconAsset: icon,
                contentType: type,
                sourceType: "audio",
                duration: structuredTranscription.duration,
                transcriptionUri,
                keywords,
                descriptionAudio: description,
                summaryLanguage,
                createdAt: new Date()
            });

            await consumeUserCredit(userId);

            return successResponse(res, {
                minuteId,
                transcription: structuredTranscription,
                keywords,
                description
            }, "Audio uploaded and transcribed successfully.");

        } catch (error) {
            console.error("🔥 [uploadAudio] ElevenLabs error:", error.response?.data || error.message);
            return res.status(500).json(errorResponse(error.response?.data?.error || error.message || "Internal Server Error"));
        }
    });
};