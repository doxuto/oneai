const Busboy = require('busboy');

/**
 * Middleware: Handles single PDF upload via raw multipart/form-data using Busboy
 */
exports.uploadPDF = async (req, res, next) => {
  const busboy = Busboy({
    headers: req.headers,
    limits: { fileSize: 20 * 1024 * 1024 }, // Max: 20MB
  });

  let fileBuffer = Buffer.alloc(0);
  const fields = {};
  let fileInfo = null;

  // 📥 Handle file stream
  busboy.on('file', (fieldname, file, filename, encoding, mimetype) => {
    // Verify file type is PDF
    // if (mimetype !== 'application/pdf') {
    //   console.warn(`🚫 Unsupported file type: ${mimetype}`);
    //   return res.status(400).json({ message: 'Only PDF files are allowed.' });
    // }

    fileInfo = {
      fieldname,
      originalname: filename?.filename || filename,
      encoding,
      mimetype,
    };

    file.on('data', (data) => {
      fileBuffer = Buffer.concat([fileBuffer, data]);
    });

    file.on('end', () => {
      console.log(`📄 Uploaded file: ${fileInfo.originalname} (${mimetype})`);
    });
  });

  // 📝 Handle regular form fields
  busboy.on('field', (fieldname, val) => {
    fields[fieldname] = val;
    console.log(`🧾 Field: ${fieldname} = ${val}`);
  });

  // ✅ Finished parsing
  busboy.on('finish', () => {
    if (!fileInfo || fileBuffer.length === 0) {
      console.warn('⚠️ No valid PDF file uploaded.');
      return res.status(400).json({ message: 'No PDF file uploaded.' });
    }

    req.file = { ...fileInfo, buffer: fileBuffer };
    req.body = fields;

    console.log('✅ Upload and field parsing complete.');
    next();
  });

  // ❌ Error handler
  busboy.on('error', (err) => {
    console.error('❌ Busboy error:', err);
    return res.status(500).json({ message: `Busboy error: ${err.message}` });
  });

  // 📡 Handle raw body or stream
  if (req.rawBody) {
    busboy.end(req.rawBody);
  } else {
    req.pipe(busboy);
  }

  // ⚠️ Client disconnect handler
  req.on('close', () => {
    if (req.aborted) {
      console.warn('⚠️ Client disconnected during upload.');
    }
  });
};