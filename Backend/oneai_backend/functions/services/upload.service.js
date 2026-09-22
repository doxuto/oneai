const { bucket } = require('../config/config-firebase');
const { v4: uuidv4 } = require('uuid');


exports.uploadFileToFolder = async ({
    userId = null,
    minuteId = null,
    file: fileBinary,
    fileName = null,
    contentType = 'application/octet-stream'
}) => {
    if (!userId) return null;
    if (!fileBinary || fileBinary.length === 0) return null;
    if (!fileName) fileName = generateToken();

    try {
        const _minuteId = minuteId || generateToken();
        const uniqueFileName = `${Date.now()}-${fileName}`;
        const destination = `user_uploads/${userId}/${_minuteId}/audio/${uniqueFileName}`;
        const file = bucket.file(destination);

        // ✅ Upload file
        await file.save(fileBinary, {
            contentType: contentType,
            metadata: {
                metadata: {
                    firebaseStorageDownloadTokens: generateToken(),
                },
            },
        });


        const gcsUri = `gs://${bucket.name}/${destination}`; 

        console.log(`✅ gcsUri: ${gcsUri}`);
        console.log(`🌐 MinuteId: ${_minuteId}`);

        return {
            _minuteId,
            gcsUri
        };

    } catch (error) {
        console.error('❌ Lỗi khi tải file lên Storage:', error);
        return null;
    }
};

exports.uploadJsonToFolder = async ({
    userId = null,
    fileName = null,
    data = {},
    minuteId = null,
    type = 'json'  // 👈 'transcription' | 'summary' | default fallback
}) => {
    if (!userId || !fileName || !data || !minuteId) return null;

    try {
        const subFolder = ['transcription', 'summary'].includes(type) ? type : 'json';
        const destination = `user_uploads/${userId}/${minuteId}/${subFolder}/${fileName}.json`;
        const file = bucket.file(destination);

        await file.save(JSON.stringify(data), {
            contentType: 'application/json',
            metadata: {
                metadata: {
                    firebaseStorageDownloadTokens: generateToken(),
                },
            },
        });

        const gcsUri = `gs://${bucket.name}/${destination}`;
        console.log(`✅ JSON gcsUri: ${gcsUri}`);
        return gcsUri;

    } catch (error) {
        console.error('❌ Error uploading JSON file:', error);
        return null;
    }
};

exports.uploadPDFToFolder = async ({
    userId = null,
    minuteId = null,
    file: fileBinary,
    fileName = null,
    contentType = null
}) => {
    if (!userId) {
        console.error('❌ Upload failed: Missing userId.');
        return null;
    }

    if (!fileBinary || fileBinary.length === 0) {
        console.error('❌ Upload failed: File binary is empty or undefined.');
        return null;
    }

    if (!fileName) {
        fileName = generateToken();
        console.log(`📄 No file name provided. Generated fileName: ${fileName}`);
    }

    try {
        const _minuteId = minuteId || generateToken();
        if (!minuteId) {
            console.log(`🆔 No minuteId provided. Generated new minuteId: ${_minuteId}`);
        }

        const uniqueFileName = `${Date.now()}-${fileName}`;
        const destination = `user_uploads/${userId}/${_minuteId}/pdf/${uniqueFileName}`;
        const file = bucket.file(destination);

        console.log(`📤 Preparing to upload file to GCS path: ${destination}`);

        // ✅ Upload file
        await file.save(fileBinary, {
            contentType: contentType,
            metadata: {
                metadata: {
                    firebaseStorageDownloadTokens: generateToken(),
                },
            },
        });

        const gcsUri = `gs://${bucket.name}/${destination}`;
        return {
            _minuteId,
            gcsUri
        };

    } catch (error) {
        console.error('❌ Error occurred during file upload to Cloud Storage.');
        console.error(error);
        return null;
    }
};

function generateToken() {
    return uuidv4();
}

