const admin = require('firebase-admin');
const { errorResponse } = require("../utils/responseHelper");

exports.authMiddleware = async (req, res, next) => {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        console.warn("⚠️ [authMiddleware] Missing or malformed Authorization header");
        return res.status(401).json(errorResponse("Unauthorized. Missing Bearer token."));
    }

    const token = authHeader.split(' ')[1];

    try {
        const decodedToken = await admin.auth().verifyIdToken(token);
        req.user = decodedToken;
        console.log(`✅ [authMiddleware] User authenticated: ${decodedToken.user_id}`);
        next();
    } catch (error) {
        console.error("❌ [authMiddleware] Error verifying token:", error.message);
        return res.status(401).json(errorResponse("Unauthorized. Invalid or expired token."));
    }
};