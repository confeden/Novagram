// NovaGram relay Worker (v2).
//
// Telegram WSS relay on kws*.nova-app.eu. A client proves it holds an install
// credential by offering a second WebSocket subprotocol:
//   Sec-WebSocket-Protocol: binary, nova2.<payload>.<signature>
// payload   = base64url(JSON {"v":2,"i":<install id>,"e":<expiry unix s>,"q":<upgrades per UTC day>})
// signature = base64url(Ed25519(issuer private key, "nova2." + payload))
//
// The Worker holds only PUBLIC keys. Nothing in a client or in this Worker can mint a
// token; the issuer (nova-app.eu VPS) signs, sets each install's daily quota and stops
// refreshing a revoked install, whose last token dies within its TTL.
//
// Bindings: PUBKEYS (var, comma-separated base64url raw Ed25519 keys, newest last),
// COUNTER (Durable Object), GLOBAL_DAILY_CAP (var), KILL (var, "1" = refuse everything).

const TOKEN_PREFIX = "nova2.";
const HOST_RE = /^kws(\d+)(-1)?\.nova-app\.eu$/;
const MAX_TOKEN_LEN = 512;

const enc = new TextEncoder();

export function b64uToBytes(s) {
  if (!/^[A-Za-z0-9_-]*$/.test(s)) throw new Error("base64url");
  const pad = "=".repeat((4 - (s.length % 4)) % 4);
  const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/") + pad);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

const keyCache = new Map();
async function importKey(raw) {
  let k = keyCache.get(raw);
  if (!k) {
    k = crypto.subtle.importKey("raw", b64uToBytes(raw), { name: "Ed25519" }, false, ["verify"]);
    keyCache.set(raw, k);
  }
  return k;
}

// Returns {ok:true, id, quota, exp} or {ok:false, reason}.
export async function checkToken(offered, pubkeys, nowSec) {
  const item = offered.find((p) => p.startsWith(TOKEN_PREFIX));
  if (!item) return { ok: false, reason: "missing" };
  if (item.length > MAX_TOKEN_LEN) return { ok: false, reason: "malformed" };
  const parts = item.split(".");
  if (parts.length !== 3) return { ok: false, reason: "malformed" };

  let payload, sig, claims;
  try {
    payload = b64uToBytes(parts[1]);
    sig = b64uToBytes(parts[2]);
    claims = JSON.parse(new TextDecoder().decode(payload));
  } catch {
    return { ok: false, reason: "malformed" };
  }
  if (sig.length !== 64) return { ok: false, reason: "malformed" };

  const signed = enc.encode(TOKEN_PREFIX + parts[1]);
  let valid = false;
  for (const raw of pubkeys) {
    try {
      if (await crypto.subtle.verify({ name: "Ed25519" }, await importKey(raw), sig, signed)) {
        valid = true;
        break;
      }
    } catch {
      /* a bad key in the list must not block the others */
    }
  }
  if (!valid) return { ok: false, reason: "bad-signature" };

  if (claims.v !== 2 || typeof claims.i !== "string" || !/^[A-Za-z0-9_-]{8,64}$/.test(claims.i)) {
    return { ok: false, reason: "claims" };
  }
  if (!Number.isInteger(claims.e) || !Number.isInteger(claims.q) || claims.q < 0) {
    return { ok: false, reason: "claims" };
  }
  if (claims.e < nowSec) return { ok: false, reason: "expired" };
  return { ok: true, id: claims.i, quota: claims.q, exp: claims.e };
}

export function utcDay(nowSec) {
  return Math.floor(nowSec / 86400);
}

async function bump(env, name, day) {
  const stub = env.COUNTER.get(env.COUNTER.idFromName(name));
  const r = await stub.fetch("https://counter/hit?day=" + day);
  return Number(await r.text());
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const host = url.hostname.toLowerCase();

    // One uniform reply for every rejection: a scanner cannot tell a wrong hostname
    // from a missing signature.
    const reject = (reason) => {
      console.log(JSON.stringify({ reject: reason, host }));
      return new Response("not found", { status: 404 });
    };

    if (env.KILL === "1") return reject("kill");
    if (url.pathname !== "/apiws") return reject("path");
    if ((request.headers.get("Upgrade") || "").toLowerCase() !== "websocket") return reject("upgrade");
    const match = host.match(HOST_RE);
    if (!match) return reject("host");

    const offered = (request.headers.get("Sec-WebSocket-Protocol") || "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
    if (!offered.includes("binary")) return reject("subprotocol");

    const now = Math.floor(Date.now() / 1000);
    const pubkeys = (env.PUBKEYS || "").split(",").map((s) => s.trim()).filter(Boolean);
    const t = await checkToken(offered, pubkeys, now);
    if (!t.ok) return reject("token-" + t.reason);

    // Quotas are counted only for a valid signature, so junk never reaches storage.
    const day = utcDay(now);
    const used = await bump(env, "i:" + t.id, day);
    if (used > t.quota) {
      console.log(JSON.stringify({ over: t.id, used, quota: t.quota }));
      return new Response(null, { status: 429, headers: { "Retry-After": "3600" } });
    }
    const cap = Number(env.GLOBAL_DAILY_CAP || 300000);
    if ((await bump(env, "global", day)) > cap) {
      console.log(JSON.stringify({ over: "global", cap }));
      return new Response(null, { status: 503, headers: { "Retry-After": "3600" } });
    }

    const upstreamHost = `kws${match[1]}${match[2] || ""}.web.telegram.org`;
    const headers = new Headers(request.headers);
    // Telegram must never see Nova's credential - forward the plain subprotocol.
    headers.set("Sec-WebSocket-Protocol", "binary");
    headers.delete("Origin");
    headers.delete("Referer");
    try {
      const response = await fetch(`https://${upstreamHost}${url.pathname}${url.search}`, {
        method: request.method,
        headers,
      });
      if (response.status === 101) return response;
      console.log(JSON.stringify({ upstream: upstreamHost, status: response.status }));
    } catch (err) {
      console.log(JSON.stringify({ upstream: upstreamHost, error: String(err && err.message) }));
    }
    return new Response("not found", { status: 404 });
  },
};

// One instance per install id plus one named "global". Holds only today's count.
export class Counter {
  constructor(state) {
    this.state = state;
  }
  async fetch(request) {
    const day = new URL(request.url).searchParams.get("day");
    const cur = (await this.state.storage.get("c")) || { day: "", n: 0 };
    const next = cur.day === day ? { day, n: cur.n + 1 } : { day, n: 1 };
    await this.state.storage.put("c", next);
    return new Response(String(next.n));
  }
}
