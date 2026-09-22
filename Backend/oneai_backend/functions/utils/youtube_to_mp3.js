const axios = require("axios");
const https = require("https");
const cheerio = require("cheerio");
const { SocksProxyAgent } = require("socks-proxy-agent");
const vm = require("vm");
const { getAuthorizationInfo } = require('./authDetector'); // đường dẫn đúng với bạn

// Helpers
function atob(str) {
  return Buffer.from(str, "base64").toString("binary");
}
function btoa(str) {
  return Buffer.from(str, "binary").toString("base64");
}

function extractVideoId(url) {
  const regex = /(?:v=|youtu\.be\/|embed\/)([\w-]{11})/;
  const match = url.match(regex);
  if (!match || !match[1]) throw new Error("❌ Invalid YouTube URL");
  return match[1];
}

function decodeHex(raw) {
  if (!raw) return '';

  // ① Nếu là mảng: ['0x56','0x36',…] → nối thành chuỗi có khoảng trắng
  let hexString = Array.isArray(raw) ? raw.join(' ') : String(raw);

  const matches = hexString.match(/0x[a-fA-F0-9]{2}/g) || [];
  return matches.map(h => String.fromCharCode(parseInt(h, 16))).join('');
}

async function generateAuthorizationFromHTML(html) {
  const $ = cheerio.load(html);

  /* 1️⃣  Lấy đúng script inline khai báo var gC & LVy */
  const inlineScript = $('script')
    .map((_, el) => $(el).html())
    .get()
    .find(txt => txt && txt.includes('var gC') && txt.includes('LVy'));
  if (!inlineScript) throw new Error('❌ Inline script with gC not found');

  /* 2️⃣  Eval script để lấy gC */
  const sandbox = { gC: {}, atob, btoa };
  vm.createContext(sandbox);
  new vm.Script(inlineScript).runInContext(sandbox);

  const { gC } = sandbox;
  if (!gC?.d) throw new Error('❌ gC not initialized');

  /* 3️⃣  Các mảng cấu hình */
  const d1 = gC.d(1);  // ["binString", "base64Secret"]
  const d2 = gC.d(2);  // [flagReverse, shift, truncate, casing]
  const d3 = gC.d(3);  // ["0x..(sK)", "0x..(paramKey)"]

  /* 4️⃣  Tính authorizationKey (giống hàm authorization() bên y2mate.js) */
  const indices = decodeBin(d1[0]);
  let secret = parseInt(d2[0]) > 0
    ? atob(d1[1]).split('').reverse().join('')
    : atob(d1[1]);

  let t = '';
  indices.forEach(i => (t += secret[i - d2[1]]));
  if (d2[2] > 0) t = t.substring(0, d2[2]);

  const sK = decodeHex(d3[0]);      // secret hex
  let authorizationKey;
  switch (d2[3]) {
    case 0: authorizationKey = btoa(`${t}_${sK}`); break;
    case 1: authorizationKey = btoa(`${t.toLowerCase()}_${sK}`); break;
    case 2: authorizationKey = btoa(`${t.toUpperCase()}_${sK}`); break;
    default: throw new Error('❌ Unknown casing flag');
  }

  function decodeBin(str) {
    return str.split(" ").map(bin => parseInt(bin, 2));
  }

  /* 5️⃣  Trả về key & param */
  return {
    authorizationKey,          // giá trị gửi lên init
    paramKey: decodeHex(d3[1]) // tên query param
    // Không còn header x-auth-* dưới layout mới
  };
}

async function generateAuthorization() {
  const proxy = process.env.PROXY || '' /* credential removed 2026-09-23 — YouTube ingest dropped; rotate at the provider, it is still in git history */;
  const agent = new SocksProxyAgent(proxy);
  agent.options.rejectUnauthorized = false;

  const res = await axios.get("https://y2mate.nu/", {
    headers: {
      "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Encoding": "gzip, deflate, br",
      "Accept-Language": "en-GB,en-US;q=0.9,en;q=0.8",
      "Connection": "keep-alive",
      "Host": "y2mate.nu",
      "Sec-Fetch-Dest": "document",
      "Sec-Fetch-Mode": "navigate",
      "Sec-Fetch-Site": "none",
      "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
    },
    httpsAgent: agent,
    httpAgent: agent
  });

  return await getAuthorizationInfo(res.data, agent);
}

// Polling logic
async function pollProgress(progressURL, headers, agent, maxAttempts = 10, interval = 3000) {
  console.log("🔄 Polling progress URL:", progressURL);
  for (let i = 0; i < maxAttempts; i++) {
    console.log(`🔁 Attempt ${i + 1}/${maxAttempts}`);
    const res = await axios.get(progressURL, { headers, httpsAgent: agent, httpAgent: agent });
    const data = res.data;
    if (data.downloadURL) return data;
    if (data.error && data.error !== 0) throw new Error(`Progress error: ${data.error}`);
    await new Promise(resolve => setTimeout(resolve, interval));
  }
  throw new Error("Timeout waiting for downloadURL");
}

// Main function
async function getYoutubeMp3DownloadURL(youtubeUrl) {
  console.log("📥 Starting download process for URL:", youtubeUrl);

  const proxy = process.env.PROXY || '' /* credential removed 2026-09-23 — YouTube ingest dropped; rotate at the provider, it is still in git history */;
  const agent = new SocksProxyAgent(proxy);
  agent.options.rejectUnauthorized = false;
  console.log("🌐 Proxy agent initialized.");

  const videoId = extractVideoId(youtubeUrl);
  console.log("✅ Extracted video ID:", videoId);

  const headers = {
    "Accept": "*/*",
    "Accept-Encoding": "gzip, deflate, br",
    "Accept-Language": "en-GB,en-US;q=0.9,en;q=0.8",
    "Connection": "keep-alive",
    "Host": "d.mnuu.nu",
    "Origin": "https://y2mate.nu",
    "Referer": "https://y2mate.nu/",
    "Sec-Fetch-Dest": "empty",
    "Sec-Fetch-Mode": "cors",
    "Sec-Fetch-Site": "cross-site",
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
  };

  const { authorizationKey, headerKey, headerVal, paramKey } = await generateAuthorization();
  if (headerKey && headerVal) {
    headers[`x-auth-${headerKey}`] = headerVal;
  }

  const initUrl = `https://d.mnuu.nu/api/v1/init?${paramKey}=${authorizationKey}&_=${Math.random()}`;

  console.log("🚀 Sending init request to:", initUrl);



  const response = await axios.get(initUrl, { headers, httpsAgent: agent, httpAgent: agent });
  const convertURL = response.data.convertURL;
  if (!convertURL) throw new Error("❌ Failed to get convertURL from init response.");
  console.log("📨 Received convertURL:", convertURL);

  const convertFullUrl = `${convertURL}&v=${videoId}&f=mp3&_=${Math.random()}`;

  // 🔁 Retry loop
  let progressURL, downloadURL, redirect, redirectURL;
  const maxRetries = 60;
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    console.log(`🔁 Attempt ${attempt}: Sending convert request to:`, convertFullUrl);

    const convertRes = await axios.get(convertFullUrl, {
      headers,
      httpsAgent: new https.Agent({ rejectUnauthorized: false }),
      httpAgent: agent,
      validateStatus: () => true
    });

    ({ progressURL, downloadURL, redirect, redirectURL } = convertRes.data || {});

    console.log("📬 Convert response received.", {
      progressURL,
      downloadURL,
      redirect,
      redirectURL
    });

    // ✅ Case 1: Có downloadURL luôn
    if (downloadURL) {
      console.log("✅ Found download URL:", downloadURL);
      return { success: true, data: { downloadURL } };
    }

    // ✅ Case 2: Redirect sang nơi khác
    if (redirect === 1 && redirectURL) {
      console.log("🔀 Redirecting to:", redirectURL);
      const redirected = await axios.get(redirectURL, { headers, httpsAgent: agent, httpAgent: agent });
      progressURL = redirected.data?.progressURL;
      downloadURL = redirected.data?.downloadURL;

      console.log("↪️ After redirect:", {
        progressURL,
        downloadURL
      });

      if (downloadURL) return { success: true, data: { downloadURL } };
      if (progressURL) break; // Sẵn sàng để poll
    }

    // ❌ Nếu vẫn chưa có gì, thử lại sau 1 giây
    if (!progressURL && !downloadURL) {
      console.warn(`⚠️ Missing progressURL/downloadURL on attempt ${attempt}, retrying in 1s...`);
      await new Promise(resolve => setTimeout(resolve, 1000));
    } else {
      break;
    }
  }

  // ❌ Nếu sau retry vẫn chưa có progressURL
  if (!progressURL) {
    console.error("❌ Missing progress URL after retries.");
    throw new Error("Missing progress URL after multiple retries");
  }

  console.log("⏳ Polling progress URL to get final download link...");
  const finalData = await pollProgress(progressURL, headers, agent);
  console.log("🎉 Final download URL obtained:", finalData.downloadURL);

  return { success: true, data: { downloadURL: finalData.downloadURL } };
}

module.exports = { getYoutubeMp3DownloadURL };