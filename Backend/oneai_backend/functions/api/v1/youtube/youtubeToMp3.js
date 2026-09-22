const { getYoutubeMp3DownloadURL } = require('../../../utils/youtube_to_mp3');

module.exports = async function (req, res) {
  try {
    const { youtubeUrl } = req.body;
    if (!youtubeUrl) {
      return res.status(400).json({ success: false, message: 'Missing youtubeUrl' });
    }

    const link = await getYoutubeMp3DownloadURL(youtubeUrl);
    return res.json({ success: true, downloadURL: link });
  } catch (err) {
    console.error('youtube-to-mp3 error:', err);
    return res.status(500).json({ success: false, message: err.message });
  }
};