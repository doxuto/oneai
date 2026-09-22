const tagService = require('../../../services/tag.service');
module.exports = async (req, res) => {
  await tagService.deleteTag(req, res);
  res.json({ success: true });
};
