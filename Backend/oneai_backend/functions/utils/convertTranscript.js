function convertElevenLabsToSections(data) {
  if (!data.words || !Array.isArray(data.words)) {
    throw new Error("❌ Invalid input format: 'words' field missing or not an array");
  }

  console.log("📥 [convertElevenLabsToSections] Start processing...");
  const result = {
    duration: "00:00",
    sections: [],
  };

  let currentSpeaker = null;
  let currentWords = [];
  let startTime = null;
  let endTime = null;

  for (const word of data.words) {
    if (word.type !== "word") continue;

    if (currentSpeaker === null) {
      // Start first section
      currentSpeaker = word.speaker_id;
      startTime = parseFloat(word.start);
      endTime = parseFloat(word.end);
      currentWords.push(word.text);

    } else if (word.speaker_id === currentSpeaker) {
      // Continue same speaker section
      currentWords.push(word.text);
      endTime = parseFloat(word.end);
    } else {
      // Finalize and store the current section
      const section = {
        timeRange: `${formatTime(startTime)} - ${formatTime(endTime)}`,
        title: currentWords.join(" "),
        speaker: formatSpeaker(currentSpeaker),
        speaker_id: formatSpeakerId(currentSpeaker)
      };
      result.sections.push(section);

      // Start new section
      currentSpeaker = word.speaker_id;
      currentWords = [word.text];
      startTime = parseFloat(word.start);
      endTime = parseFloat(word.end);
    }
  }

  // Push final section
  if (currentWords.length > 0) {
    const section = {
      timeRange: `${formatTime(startTime)} - ${formatTime(endTime)}`,
      title: currentWords.join(" "),
      speaker: formatSpeaker(currentSpeaker),
      speaker_id: formatSpeakerId(currentSpeaker)
    };
    result.sections.push(section);
    console.log(`✅ Final section saved:`, section);
  }

  // Set total duration
  const lastWord = [...data.words].reverse().find(w => w.type === "word");
  if (lastWord) {
    result.duration = formatTime(parseFloat(lastWord.end));
    console.log(`⏱️ Duration set to: ${result.duration}`);
  }

  result.transcript = data.text;
  result.language_code = data.language_code;
  result.language_probability = data.language_probability;

  console.log("🎉 [convertElevenLabsToSections] Done!");
  return result;
}

function formatTime(seconds) {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
}

function formatSpeaker(speakerId) {
  const match = speakerId.match(/\d+/);
  return match ? `Speaker ${parseInt(match[0], 10) + 1}` : speakerId;
}

function formatSpeakerId(speaker) {
  const match = speaker.match(/\d+/);
  return match ? `speaker_${parseInt(match[0], 10)}` : speaker;
}

module.exports = {
  convertElevenLabsToSections
};
