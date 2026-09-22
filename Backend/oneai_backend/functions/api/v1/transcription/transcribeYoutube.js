// ✅ YouTube MP3 Downloader + Transcriber using downloadURL
const axios = require("axios");
const { v4: uuidv4 } = require("uuid");
const FormData = require("form-data");
const { summarizeFromTranscript } = require("../../../services/ai.service");
const { convertElevenLabsToSections } = require("../../../utils/convertTranscript");
const { successResponse, errorResponse } = require("../../../utils/responseHelper");
const { db } = require("../../../config/config-firebase");
const uploadService = require("../../../services/upload.service");
const { getYoutubeMp3DownloadURL } = require("../../../utils/youtube_to_mp3");
const { checkUserCanUseCredit, consumeUserCredit } = require("../../../utils/checkAndConsumeUserCredit");
const { getAudioDurationFromBuffer } = require("../../../utils/getAudioDuration");
const { upsertMinute } = require('../../../services/minutes.service');

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

module.exports = async (req, res) => {
  const { youtubeUrl, audioLanguage = "auto-detect", summaryLanguage = "auto-detect", keywords = "", description = "" } = req.body;
  const userId = req.user?.user_id;
  if (!youtubeUrl || typeof youtubeUrl !== "string") return errorResponse(res, "Missing or invalid YouTube URL");

  if (!req.user?.user_id) {
    console.warn("⚠️ [uploadAudio] Missing authenticated user.");
    return unauthorizedResponse(res);
  }

  const timezone = req.headers['X-Timezone'] || req.body.timezone || "GMT -7";


  try {
    const check = await checkUserCanUseCredit(userId);
    if (!check.allowed) {
      console.warn(`⛔ User ${userId} exceeded credit limit.`);
      return res.status(402).json(errorResponse("You have no credits left. Please upgrade your plan."));
    }
    console.log(`✅ User authorized with plan: ${check.plan}, remaining credit: ${check.credit}`);
  } catch (err) {
    console.error("❌ Credit check error:", err.message);
    return res.status(500).json(errorResponse("Failed to check user credit."));
  }


  const minuteId = uuidv4();
  const filename = uuidv4();

  try {
    console.log("🎬 [transcribeYoutube] Getting MP3 download URL...");
    const { success, data } = await getYoutubeMp3DownloadURL(youtubeUrl);
    if (!success || !data.downloadURL) throw new Error("❌ Failed to get download URL");

    const downloadURL = data.downloadURL;

    const headers = {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15',
      'Referer': 'https://y2mate.nu/',
      'Origin': 'https://y2mate.nu',
      'Accept': '*/*',
      'Accept-Language': 'en-GB,en-US;q=0.9,en;q=0.8',
      'Accept-Encoding': 'gzip, deflate, br',
      'Sec-Fetch-Site': 'cross-site',
      'Sec-Fetch-Dest': 'empty',
      'Sec-Fetch-Mode': 'cors',
      'Connection': 'keep-alive'
    };

    const maxRetries = 5;
    let attempt = 0;
    let buffer;
    let response;

    while (attempt < maxRetries) {
      try {
        console.log(`🔁 Attempt ${attempt + 1}: Downloading MP3...`);
        response = await axios({
          method: 'get',
          url: downloadURL,
          responseType: 'arraybuffer',
          headers,
          timeout: 20000,
        });

        if (response.status === 200 && response.data && response.data.length > 0) {
          buffer = response.data;
          console.log("✅ MP3 download complete");
          break;
        } else {
          throw new Error(`Invalid response: status=${response.status}, size=${response.data?.length}`);
        }
      } catch (err) {
        console.warn(`⚠️ Download attempt ${attempt + 1} failed:`, err.message);
        attempt++;
        if (attempt === maxRetries) {
          throw new Error("❌ Failed to download valid MP3 after multiple attempts.");
        }
        await new Promise(resolve => setTimeout(resolve, 1500)); // đợi 1.5s rồi thử lại
      }
    }
    console.log("📎 Response Content-Type:", response.headers['content-type']);
    console.log("📎 Response Status:", response.status);
    if (response.status !== 200) {
      throw new Error(`Download failed with status code ${response.status}`);
    }

    const sizeMB = (buffer.length / (1024 * 1024)).toFixed(2);
    console.log(`📦 Audio size: ${sizeMB} MB`);
    console.log("✅ MP3 download complete");


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


    

    //// Not upload to GCS 
    // console.log("📤 Uploading MP3 to GCS before transcription...");
    // const uploadResult = await uploadService.uploadFileToFolder({
    //   userId,
    //   minuteId,
    //   file: buffer,
    //   fileName: `${filename}.mp3`,
    //   contentType: 'audio/mpeg'
    // });
    // console.log("✅ Uploaded to GCS:", uploadResult);
    // const gcsUri = uploadResult.gcsUri;

    const langCode = audioLanguage.split("-")[0].toLowerCase();
    const mappedLang = languageMap[langCode] || null;
    const form = new FormData();
    form.append("model_id", "scribe_v1");
    form.append("file", buffer, { filename: "audio.mp3", contentType: "audio/mpeg" });
    form.append("diarize", "true");
    form.append("tag_audio_events", "true");
    if (mappedLang) form.append("language_code", mappedLang);

    console.log("📤 Sending audio to ElevenLabs...");
    let elevenRes;
    try {
      elevenRes = await axios.post("https://api.elevenlabs.io/v1/speech-to-text", form, {
        headers: { ...form.getHeaders(), "xi-api-key": process.env.ELEVENLABS_API_KEY },
        timeout: 600000,
        maxContentLength: Infinity,
        maxBodyLength: Infinity
      });
    } catch (err) {
      console.error("🛑 ElevenLabs API error:", err.response?.data || err.message);
      throw new Error("❌ ElevenLabs API error");
    }

    const structuredTranscription = convertElevenLabsToSections(elevenRes.data);
    const transcript = JSON.stringify(structuredTranscription, null, 2);
    const summaryJson = JSON.parse(await summarizeFromTranscript(transcript, summaryLanguage, description, timezone));


    const transcriptionUri = await uploadService.uploadJsonToFolder({
      userId,
      fileName: 'transcription',
      data: elevenRes.data,
      minuteId,
      type: 'transcription'
    });

    // const summaryUri = await uploadService.uploadJsonToFolder({
    //   userId,
    //   fileName: 'summary',
    //   data: summaryJson,
    //   minuteId,
    //   type: 'summary'
    // });

    // 👉 Save full JSON object as transcript
    await upsertMinute(userId, minuteId, structuredTranscription, summaryJson, {
      title: summaryJson.title,
      minuteId,
      gcsUri: null,
      iconAsset: summaryJson.icon,
      contentType: summaryJson.type,
      sourceType: "youtube",
      duration: structuredTranscription.duration,
      transcriptionUri,
      keywords,
      descriptionAudio: description,
      summaryLanguage,
      createdAt: new Date()
    });

    await consumeUserCredit(userId);

    return successResponse(res, { minuteId, transcription: structuredTranscription }, "Transcription from YouTube completed.");
  } catch (err) {
    console.error("🔥 Error in transcribeYoutube:", err);
    return res.status(500).json(errorResponse(err.message || "Failed to process YouTube transcription"));
  }
};
