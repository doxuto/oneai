import { generateKeyPairSync, sign } from "node:crypto";

export function makeSigner(keyId = 3335741209) {
  const { publicKey, privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const pem = publicKey.export({ type: "spki", format: "pem" }).toString();
  function signQuery(message: string): string {
    const der = sign("sha256", Buffer.from(message, "utf8"), { key: privateKey, dsaEncoding: "der" });
    return der.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }
  function query(params: Record<string, string>): string {
    const message = new URLSearchParams({ ...params, key_id: String(keyId) }).toString();
    return `${message}&signature=${signQuery(message)}`;
  }
  const fetchKeys: typeof fetch = async () => new Response(JSON.stringify({ keys: [{ keyId, pem }] }), { status: 200 });
  return { keyId, pem, signQuery, query, fetchKeys };
}
