module.exports = async (req, res) => {
  res.json({ title: "Demo Meeting", date: new Date().toISOString(), duration: "15:00", transcript: { messages: [] }, meetingMinute: { title: "Demo", date: new Date().toISOString(), duration: "15:00", sections: [] } });
};
