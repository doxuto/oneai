const { body, validationResult } = require('express-validator');

const handleValidationErrors = (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
        return res.status(400).json({ errors: errors.array() });
    }
    next();
};

exports.addMinutesValidation = [
    body('timestamp').notEmpty().withMessage('timestamp Không được để trống')
    ,body('duration').notEmpty().withMessage('duration Không được để trống')
    , handleValidationErrors]