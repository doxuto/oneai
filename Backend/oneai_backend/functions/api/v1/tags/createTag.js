const tagService = require('../../../services/tag.service');

module.exports = async (req, res) => {
  return tagService.createTag(req, res);
};