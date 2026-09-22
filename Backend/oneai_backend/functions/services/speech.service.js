
const speech = require('@google-cloud/speech');
const speechV2 = speech.v2;
const { summarizeText } = require("../services/ai.service");
const { db, bucket } = require("../config/config-firebase");

const client = new speechV2.SpeechClient({
    keyFilename: "./service-account.json" // ✔️ local dev
});

exports.transcribeAudio = async (userId, minuteId, gcsUri, keywords, description, audioLanguage = "en-US", summaryLanguage = "en-US") => {
    console.log("🚀 [transcribeAudio] Start...");
    console.log(`👉 userId: ${userId}`);
    console.log(`👉 gcsUri: ${gcsUri}`);

    if (!gcsUri.startsWith("gs://")) throw new Error("Invalid GCS URI");

    const recognizer = `projects/minutesai-6715a/locations/global/recognizers/my-global-recognizer`;
    const gcOutputFolder = `gs://minutesai-6715a.firebasestorage.app/user_uploads/${userId}/${minuteId}/transcription`;

    const phrases = [
        ...keywords.map(word => ({ value: word, boost: 15.0 })),
        ...(description ? [{ value: description, boost: 5.0 }] : []),
    ];

    const request = {
        recognizer,
        files: [{ uri: gcsUri }],
        config: { autoDecodingConfig: {},
         languageCodes: [audioLanguage],
         speechContexts: phrases.length > 0 ? [{ phrases }] : [] },
         diarizationConfig: {
            enableSpeakerDiarization: true,
            minSpeakerCount: 1, 
            maxSpeakerCount: 10
        },
        recognitionOutputConfig: { gcsOutputConfig: { uri: gcOutputFolder } }
    };

    console.log("📤 Sending batchRecognize request...");
    const [operation] = await client.batchRecognize(request);
    console.log(`✅ Operation created: ${operation.name}`);

    const operationId = operation.name.split("/").pop();
    await db.collection("speechJobs").doc(operationId).set({
        userId,
        minuteId,
        keywords,
        description,
        audioLanguage,
        summaryLanguage,
        gcsUri,
        gcOutputFolder,
        operationId: operationId,
        status: "IN_PROGRESS",
        createdAt: new Date(),
        lastCheckedAt: new Date()
    });

    console.log("✅ Firestore job record created");
    return operation.name;
};

exports.pollTranscriptionStatus = async (operationId) => {
    console.log(`📥 [pollTranscriptionStatus] Checking operation: ${operationId}`);

    console.log(`🔎 Fetching operation status for ID: ${operationId}`);
    const [operation] = await client.operationsClient.getOperation({ name: operationId });

    console.log(`ℹ️ Operation response received for ${operationId}:`);
    console.log(`    - done: ${operation.done}`);
    console.log(`    - metadata: ${JSON.stringify(operation.metadata)}`);
    console.log(`    - response: ${JSON.stringify(operation.response)}`);

    if (!operation.done) {
        console.log(`🕑 Transcription job ${operationId} is still running...`);
        return { status: "IN_PROGRESS" };
    }

    if (!operation.response || !operation.response.value) {
        console.error(`❌ No response value found in operation ${operationId}`);
        return { status: "FAILED" };
    }

    console.log(`✅ Operation ${operationId} completed, decoding response...`);

    // ✅ PARSE BUFFER
    const buffer = operation.response.value;
    const decodedResponse = speech.protos.google.cloud.speech.v2.BatchRecognizeResponse.decode(buffer);

    console.log(`📄 BatchRecognizeResponse parsed.`);
    console.log('📥 decodedResponse:', decodedResponse);

    // ✅ Extract transcription file URI from response
    const fileResults = decodedResponse.results;
    const audioUris = Object.keys(fileResults);
    if (!audioUris.length) throw new Error("❌ No file results found in BatchRecognizeResponse");

    const firstAudioUri = audioUris[0];
    const fileResult = fileResults[firstAudioUri];

    console.log(`📥 fileResult: ${JSON.stringify(fileResult)}`);

    const resultsGcsUri = fileResult?.uri ?? "";
    if (!resultsGcsUri) throw new Error(`❌ No transcription file URI found for operation ${operationId}`);
    console.log(`✅ Found resultsGcsUri: ${resultsGcsUri}`);
    console.log('Transcript:', fileResult.transcript);

    const completedAt = new Date();
    const _operationId = operationId.split('/').pop();

    // ✅ Update Firestore
    console.log(`💾 Updating Firestore job record for operation: ${_operationId}`);
    await db.collection("speechJobs").doc(_operationId).update({
        status: "COMPLETED",
        resultsGcsUri,
        completedAt
    });

    console.log(`🎉 Transcription job ${operationId} marked as COMPLETED in Firestore.`);

    return {
        status: "COMPLETED",
        completedAt,
        resultsGcsUri
    };
};

exports.checkPendingSpeechJobs = async () => {
    console.log(`🔎 [checkPendingSpeechJobs] Starting Check jobs for client:`);

    const snapshot = await db.collection("speechJobs")
        .where("status", "==", "IN_PROGRESS")
        .get();

    if (snapshot.empty) {
        console.log("✅ No pending jobs found.");
        return;
    }

    for (const doc of snapshot.docs) {
        const job = doc.data();
        console.log(`👉 Checking job: ${doc.id}`);

        try {
            const result = await exports.pollTranscriptionStatus(job.operationId);

            if (result.status === "COMPLETED" && result.resultsGcsUri) {
                console.log(`🎉 Job ${doc.id} COMPLETED → Start reading JSON from resultsGcsUri`);

                // 👉 Parse resultsGcsUri → bucket + file path
                const match = result.resultsGcsUri.match(/^gs:\/\/([^\/]+)\/(.+)$/);
                if (!match) throw new Error(`❌ Invalid resultsGcsUri: ${result.resultsGcsUri}`);

                const bucketName = match[1];
                const filePath = match[2];
                console.log(`📥 Reading file from bucket: ${bucketName}, file: ${filePath}`);

                // 👉 Read file from GCS
                const file = bucket.file(filePath);
                const [contents] = await file.download();
                const jsonData = JSON.parse(contents.toString('utf8'));
                const extractTranscriptFromJson = (jsonData) => {
                    if (!jsonData.results || !Array.isArray(jsonData.results)) {
                        console.warn("⚠️ jsonData.results not found or not array");
                        return "";
                    }

                    const fullTranscript = jsonData.results
                        .flatMap(result => result.alternatives || [])
                        .map(alt => alt.transcript)
                        .join(" ")      

                    console.log(`✅ Extracted transcript length: ${fullTranscript.length} characters and transcript ${fullTranscript}`);
                    return fullTranscript;
                };
                const transcript = extractTranscriptFromJson(jsonData);
                console.log("📝 Starting text summarization with OpenAI...");

                const _operationId = job.operationId.split('/').pop();
                const docRef = db.collection("speechJobs").doc(_operationId);
                const docSnap = await docRef.get();

                if (!docSnap.exists) {
                    console.error(`❌ speechJob document with ID ${_operationId} not found.`);
                    return;
                }

                const speechJobData = docSnap.data();
                const keywords = speechJobData.keywords;
                const description = speechJobData.description;
                const summaryLanguage = speechJobData.summaryLanguage;

                console.log("📝 Starting text summarization with OpenAI...");
                let prompt = `You are an expert summarizer. Please provide a clear and concise summary of the following text. The text may be a meeting transcript, conversation, or classroom lecture. Summarize it in ${summaryLanguage} language:\n\n${transcript}`;

                if (keywords && keywords.length > 0) {
                    prompt += `\n\nMake sure to focus on these important keywords: ${keywords}.`;
                }

                if (description) {
                    prompt += `\n\nAdditional context about the text: ${description}.`;
                }

                prompt += `\n\nThe summary must be in '${summaryLanguage}' languageCode and capture the main points, decisions (if any), and important details. Avoid unnecessary repetition.`;

                const summary = await summarizeFromTranscript(prompt);
                console.log("✅ Summarization completed.");
                console.log("👉 Summary:", summary);
                console.log(`✅ File read successfully. Saving transcript json to Firestore users/${job.userId}/minutes/${job.minuteId}`);

                // 👉 Save full JSON object as transcript
                await db.collection("users").doc(job.userId)
                    .collection("minutes").doc(job.minuteId)
                    .set({
                        title: '',
                        minuteId: job.minuteId,
                        transcript: transcript,
                        transcription: jsonData,
                        summaryText: summary,
                        keywords: keywords,
                        descriptionAudio: description,
                        summaryLanguage: summaryLanguage,
                        completedAt: result.completedAt,
                        updatedAt: new Date()
                    }, { merge: true });

                console.log(`🎯 Transcript JSON saved for users/${job.userId}/minutes/${job.minuteId}`);

                await notifyUser(job.userId, `Speech job ${job.operationId} is completed and transcript is saved.`);
            }

        } catch (err) {
            console.error(`❌ Error checking job ${doc.id}:`, err);
        }
    }
};

async function notifyUser(userId, transcript) {
    console.log(`📢 [notifyUser] Notify user ${userId}: transcription completed.`);
    // TODO: Add your real notify logic (email, push, websocket, etc.)
}