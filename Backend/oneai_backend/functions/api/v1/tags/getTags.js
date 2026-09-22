const tagService = require('../../../services/tag.service');

module.exports = async (req, res) => {
  await tagService.getAll(req, res); // ✅ this function sends the response internally
};