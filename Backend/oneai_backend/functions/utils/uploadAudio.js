const Busboy = require('busboy');

exports.uploadAudio = async (req, res, next) => {
  const busboy = Busboy({
    headers: req.headers,
    limits: { fileSize: 200 * 1024 * 1024 }
  });

  let fileBuffer = Buffer.alloc(0);
  const fields = {};
  let fileInfo = null;

  busboy.on('file', (fieldname, file, filename, encoding, mimetype) => {
    fileInfo = {
      fieldname,
      originalname: filename.filename || filename,
      encoding,
      mimetype
    };

    file.on('data', (data) => {
      fileBuffer = Buffer.concat([fileBuffer, data]);
    });

    file.on('end', () => {
      console.log(`📁 Received file: ${fileInfo.originalname}`);
    });
  });

  busboy.on('field', (fieldname, val) => {
    console.log(`📌 Field [${fieldname}]: value = ${val}`);
    fields[fieldname] = val;
  });

  busboy.on('finish', () => {
    if (!fileInfo || fileBuffer.length === 0) {
      return res.status(400).send('No file uploaded.');
    }

    req.file = {
      ...fileInfo,
      buffer: fileBuffer
    };

    req.body = fields;

    console.log('✅ File and fields parsed successfully.');
    next();
  });

  busboy.on('error', (err) => {
    console.error('❌ Busboy error:', err);
    res.status(500).send(`Busboy error: ${err.message}`);
  });

  req.pipe(busboy); // ✅ use this in Express
  busboy.end(req.rawBody); // ✅ uncomment this instead if you're in Firebase Functions (rawBody-based)
  
  req.on('close', () => {
    if (req.aborted) {
      console.log('⚠️ Client disconnected during upload.');
    }
  });
};

