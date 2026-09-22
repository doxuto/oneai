/**
 * ✅ Standard success response
 */
exports.successResponse = (res, data = {}, message = "Success", statusCode = 200) => {
    return res.status(statusCode).json({
        success: true,
        data,
        message
    });
};

/**
 * ✅ Standard pending response for async jobs
 */
exports.pendingResponse = (res, data = {}, message = "Request accepted. Processing...") => {
    return res.status(202).json({
        success: true,
        status: "pending",
        data,
        message
    });
};

/**
 * ✅ Standard error response
 * 👉 Không có res để dùng trong catch block (return errorResponse())
 */
exports.errorResponse = (message = "Error") => ({
    success: false,
    message
});

/**
 * ✅ Standard not found response
 */
exports.notFoundResponse = (res, message = "Resource not found") => {
    return res.status(404).json({
        success: false,
        message
    });
};

/**
 * ✅ Standard unauthorized response
 */
exports.unauthorizedResponse = (res, message = "Unauthorized") => {
    return res.status(401).json({
        success: false,
        message
    });
};