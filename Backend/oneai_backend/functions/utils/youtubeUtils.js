const ytdl = require("ytdl-core");
const fs = require("fs");
const path = require("path");
const { transcribeAudio } = require("../services/speech.service");
const { v4: uuidv4 } = require("uuid");
const ffmpegPath = require("ffmpeg-static");
const { exec } = require("child_process");

exports.transcribeYoutubeAudio = async (youtubeUrl, languageCode) => {
  const tempId = uuidv4();
  const audioFilePath = path.resolve("/tmp", `${tempId}.mp3`);
  const wavFilePath = path.resolve("/tmp", `${tempId}.wav`);

  // Step 1: Download YouTube audio stream
  await new Promise((resolve, reject) => {
    const audioStream = ytdl(youtubeUrl, { filter: "audioonly" });
    const writeStream = fs.createWriteStream(audioFilePath);
    audioStream.pipe(writeStream);
    writeStream.on("finish", resolve);
    writeStream.on("error", reject);
  });

  // Step 2: Convert to WAV using ffmpeg
  await new Promise((resolve, reject) => {
    const cmd = `${ffmpegPath} -i "${audioFilePath}" -ac 1 -ar 16000 -c:a pcm_s16le "${wavFilePath}"`;
    exec(cmd, (err, stdout, stderr) => {
      if (err) return reject(err);
      resolve();
    });
  });

  // Step 3: Transcribe WAV file
  // const result = await transcribeAudio('', wavFilePath, languageCode);

  // Step 4: Cleanup temp files
  try {
    fs.unlinkSync(audioFilePath);
    fs.unlinkSync(wavFilePath);
  } catch (cleanupError) {
    console.warn("Temp file cleanup failed:", cleanupError.message);
  }

  return result;
};
