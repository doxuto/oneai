const axios = require('axios');
const cheerio = require('cheerio');
const vm = require('vm');
const { SocksProxyAgent } = require('socks-proxy-agent');

// helpers
const atob = s => Buffer.from(s, 'base64').toString('binary');
const btoa = s => Buffer.from(s, 'binary').toString('base64');
const decodeHex = raw => (Array.isArray(raw) ? raw.join(' ') : String(raw))
    .match(/0x[a-fA-F0-9]{2}/g)?.map(h => String.fromCharCode(parseInt(h, 16))).join('') || '';
const decodeBin = str => str.split(' ').map(b => parseInt(b, 2));

// --- CÁC CHIẾN LƯỢC GIẢI MÃ ---

/**
 * Strategy #1: New Inline Layout (Ưu tiên hàng đầu)
 * Layout mới nhất (giữa năm 2025).
 * Tìm script inline có 'Object.defineProperty' nhưng KHÔNG có file /auth/*.js đi kèm.
 */
function newInlineStrategy($) {
    const script = $('script').map((_, el) => $(el).html()).get()
        .find(txt => txt?.includes('var gC') && txt.includes('Object.defineProperty'));
    
    // Điều kiện quan trọng: Layout này không có file /auth/*.js
    const hasAuthJs = $('script[src^="/auth/"]').length > 0;

    if (!script || hasAuthJs) {
        return null;
    }

    const box = { gC: {}, atob };
    vm.createContext(box);
    new vm.Script(script).runInContext(box);
    const { gC } = box;
    if (!gC?.d) return null;

    const d1 = gC.d(1), d2 = gC.d(2), d3 = gC.d(3);
    if (!d1 || !d2 || !d3) return null;

    const idx = decodeBin(d1[0]);
    let secret = +d2[0] ? atob(d1[1]).split('').reverse().join('') : atob(d1[1]);
    let t = '';
    idx.forEach(i => (t += secret[i - d2[1]]));
    if (d2[2] > 0) t = t.substring(0, d2[2]);

    const sK = decodeHex(d3[0]);
    const casing = d2[3];
    const authorizationKey =
        casing === 0 ? btoa(`${t}_${sK}`) :
        casing === 1 ? btoa(`${t.toLowerCase()}_${sK}`) :
        casing === 2 ? btoa(`${t.toUpperCase()}_${sK}`) : null;

    return {
        authorizationKey,
        paramKey: decodeHex(d3[1])
    };
}


/**
 * Strategy #2: Legacy External Layout (Layout cũ có auth.js)
 * Tìm script inline có 'Object.defineProperty' VÀ một file /auth/*.js bên ngoài.
 */
async function legacyExternalStrategy($, agent) {
    const inline = $('script').map((_, el) => $(el).html()).get()
        .find(txt => txt?.includes('var gC') && txt.includes('Object.defineProperty'));
    const src = $('script[src^="/auth/"]').attr('src');
    if (!inline || !src) return null;

    const box = { gC: {}, atob };
    vm.createContext(box);
    new vm.Script(inline).runInContext(box);

    const { data: authJs } = await axios.get('https://y2mate.nu' + src, {
        httpsAgent: agent,
        httpAgent: agent,
        headers: { 'User-Agent': 'Mozilla/5.0' }
    });

    const match = authJs.match(/eval\(atob\('([^']+)'\)\)/);
    if (!match) return null;

    const env = {};
    vm.createContext(env);
    new vm.Script(atob(match[1])).runInContext(env);
    const { sH, sK, sP } = env;
    if (!sH || !sK || !sP) return null;

    const d1 = box.gC.d(1), d2 = box.gC.d(2);
    const idx = decodeBin(d1[0]);
    let secret = +d2[0] ? atob(d1[1]).split('').reverse().join('') : atob(d1[1]);
    let t = ''; idx.forEach(i => (t += secret[i - d2[1]]));
    if (d2[2] > 0) t = t.substring(0, d2[2]);

    const sKDecoded = decodeHex(sK);
    const casing = d2[3];
    const authorizationKey =
        casing === 0 ? btoa(`${t}_${sKDecoded}`) :
        casing === 1 ? btoa(`${t.toLowerCase()}_${sKDecoded}`) :
        casing === 2 ? btoa(`${t.toUpperCase()}_${sKDecoded}`) : null;

    return {
        authorizationKey,
        paramKey: decodeHex(sP),
        headerKey: decodeHex(sH[0]),
        headerVal: decodeHex(sH[1])
    };
}

/**
 * Strategy #3: Legacy Inline Layout (Layout cũ nhất có 'LVy')
 * Tìm script inline cũ nhất có chứa chuỗi 'LVy'.
 */
function legacyInlineStrategy($) {
    const script = $('script').map((_, el) => $(el).html()).get()
        .find(txt => txt?.includes('var gC') && txt.includes('LVy'));
    if (!script) return null;

    const box = { gC: {}, atob, btoa };
    vm.createContext(box);
    new vm.Script(script).runInContext(box);
    const { gC } = box;
    if (!gC?.d) return null;

    const d1 = gC.d(1), d2 = gC.d(2), d3 = gC.d(3);
    const idx = decodeBin(d1[0]);
    let secret = +d2[0] ? atob(d1[1]).split('').reverse().join('') : atob(d1[1]);
    let t = ''; idx.forEach(i => (t += secret[i - d2[1]]));
    if (d2[2] > 0) t = t.substring(0, d2[2]);

    const sK = decodeHex(d3[0]);
    const casing = d2[3];
    const authorizationKey =
        casing === 0 ? btoa(`${t}_${sK}`) :
        casing === 1 ? btoa(`${t.toLowerCase()}_${sK}`) :
        casing === 2 ? btoa(`${t.toUpperCase()}_${sK}`) : null;

    return {
        authorizationKey,
        paramKey: decodeHex(d3[1])
    };
}


/**
 * Auto layout detection
 * Tự động dò tìm layout bằng cách thử các chiến lược theo thứ tự.
 */
async function getAuthorizationInfo(html, agent) {
    const $ = cheerio.load(html);

    // Thử chiến lược inline mới nhất trước (nhanh, không cần request)
    const newInlineResult = newInlineStrategy($);
    if (newInlineResult) {
        console.log('✅ Detected: New Inline Layout');
        return newInlineResult;
    }

    // Thử chiến lược inline cũ nhất (nhanh, không cần request)
    const legacyInlineResult = legacyInlineStrategy($);
    if (legacyInlineResult) {
        console.log('✅ Detected: Legacy Inline Layout');
        return legacyInlineResult;
    }

    // Cuối cùng, thử chiến lược external (chậm hơn, cần request)
    const legacyExternalResult = await legacyExternalStrategy($, agent);
    if (legacyExternalResult) {
        console.log('✅ Detected: Legacy External Layout');
        return legacyExternalResult;
    }

    // Nếu tất cả đều thất bại, báo lỗi
    throw new Error('❌ Unknown y2mate layout – update needed');
}

module.exports = { getAuthorizationInfo };