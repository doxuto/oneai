// controllers/minutes/transcribePdf.js
const { v4: uuidv4 } = require('uuid');
const { uploadPDF } = require('../../../utils/uploadPDF');
const pdfParse = require('pdf-parse');
const {
    successResponse, errorResponse, unauthorizedResponse,
} = require('../../../utils/responseHelper');
const uploadService = require('../../../services/upload.service');
const { summarizeFromText } = require("../../../services/ai.service");
const { checkUserCanUseCredit, consumeUserCredit } = require('../../../utils/checkAndConsumeUserCredit');
const { upsertMinute } = require('../../../services/minutes.service');

module.exports = async (req, res) => {
    console.log('[transcribePdf] Waiting for uploaded PDF...');

    // 1️⃣ Receive PDF file
    uploadPDF(req, res, async (err) => {
        if (err) {
            console.error('[transcribePdf] PDF upload error:', err.message);
            return res.status(400).json(errorResponse(err.message));
        }

        if (!req.user?.user_id) {
            console.warn('[transcribePdf] Missing authenticated user');
            return unauthorizedResponse(res);
        }

        const userId = req.user.user_id;
        const minuteId = uuidv4();

        // 2️⃣ Check user credits
        try {
            const check = await checkUserCanUseCredit(userId);
            if (!check.allowed) {
                console.warn(`[transcribePdf] User ${userId} has no credits`);
                return res.status(402).json(errorResponse('You have no credits left. Please upgrade your plan.'));
            }
            console.log(`[transcribePdf] Credit OK - Plan: ${check.plan}, Remaining: ${check.credit}`);
        } catch (e) {
            console.error('[transcribePdf] Credit check failed:', e.message);
            return res.status(500).json(errorResponse('Failed to check credit.'));
        }

        // 3️⃣ Optional body params
        const {
            summaryLanguage = 'en-US',
            keywords = '',
            description = '',
            timezone = 'GMT -7',
        } = req.body;

        // 4️⃣ Parse PDF to plain text
        let extractedText = '';
        try {
            const parsed = await pdfParse(req.file.buffer);
            extractedText = parsed.text?.trim();
            if (!extractedText) throw new Error('No text extracted from PDF');
            console.log('[transcribePdf] Extracted text from PDF');
        } catch (e) {
            console.error('[transcribePdf] Failed to parse PDF:', e.message);
            return res.status(400).json(errorResponse('Failed to extract text from PDF.'));
        }

        console.log(`[transcribePdf] extractedText: ${extractedText}`);

        // 5️⃣ Summarize extracted text
        let summaryObj;
        try {
            summaryObj = JSON.parse(await summarizeFromText(
                extractedText,
                summaryLanguage,
                description,
                timezone,
            ));
            console.log('[transcribePdf] Summarization completed');
        } catch (e) {
            console.error('[transcribePdf] Summarization error:', e.message);
            return res.status(500).json(errorResponse('Failed to summarize extracted PDF text.'));
        }

        // 6️⃣ Upload raw PDF to GCS (for reference)
        let transcriptionUri;
        try {
            transcriptionUri = await uploadService.uploadPDFToFolder({
                userId,
                minuteId,
                fileName: 'raw_pdf',
                file: req.file.buffer,
                contentType: 'application/pdf',
            });
            console.log('[transcribePdf] PDF uploaded to GCS');
        } catch (e) {
            console.error('[transcribePdf] GCS upload failed:', e.message);
            return res.status(500).json(errorResponse('Failed to upload PDF to cloud.'));
        }
        
        // 7️⃣ Save to Firestore
        try {
            await upsertMinute(
                userId,
                minuteId,
                null, // no transcription sections
                summaryObj,
                {
                    title: summaryObj.title,
                    minuteId,
                    gcsUri: null,
                    iconAsset: summaryObj.icon,
                    contentType: summaryObj.type,
                    sourceType: "pdf",
                    duration: null,
                    transcriptionUri,
                    keywords,
                    descriptionAudio: description,
                    summaryLanguage,
                    createdAt: new Date(),
                },
            );

            await consumeUserCredit(userId);
            console.log('[transcribePdf] Minute saved, credit consumed');
        } catch (e) {
            console.error('[transcribePdf] Firestore save failed:', e.message);
            return res.status(500).json(errorResponse('Failed to save minute.'));
        }

        // 8️⃣ Done
        return successResponse(res, {
            minuteId,
            summary: summaryObj,
            keywords,
            description,
        }, 'PDF uploaded and summarized successfully.');
    });
};