// const minutesService = require('../../../services/minutes.service');
// const _ = require('lodash');
// module.exports = async (req, res) => {
//     const result = await minutesService.addMinutes(req.user.email,{
//         title: req.body.title,
//         duration: req.body.duration,
//         iconAsset: req.body.iconAsset,
//         tags: _.isArray(req.body.tags) ? req.body.tags : [],
//         limit: req.body.limit >= 1 ? req.body.limit : 10,
//         page: req.body.page >= 1 ? req.body.page : 1,
//     })
//     res.status(201).send({ messages: result });
// };