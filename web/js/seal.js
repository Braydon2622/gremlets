// Sealed notes for the screen bridge (the Terrarium, TERRARIUM.md): the relay (ntfy.sh) is public, so every note on a
// sealed room is AES-GCM encrypted with a key made (HKDF-SHA256) from a pairing secret that only travels inside the
// QR code / link's #fragment, bound to the room. Same scheme as the Mac's NoteSeal (GremletsCore/TerrariumNote.swift):
//   { "c": base64(ciphertext + tag), "n": base64(12-byte nonce), "v": 2 }
const enc = new TextEncoder(), dec = new TextDecoder();
const b64 = (u8) => { let s = ''; for (const b of u8) s += String.fromCharCode(b); return btoa(s); };
const unb64 = (s) => { const b = atob(s); const u = new Uint8Array(b.length); for (let i = 0; i < b.length; i++) u[i] = b.charCodeAt(i); return u; };

/** The note key for a room, from the pairing secret. */
export async function noteKey(secret, room) {
  const base = await crypto.subtle.importKey('raw', enc.encode(secret), 'HKDF', false, ['deriveKey']);
  return crypto.subtle.deriveKey({ name: 'HKDF', hash: 'SHA-256', salt: enc.encode('gremlets-terrarium-v1'), info: enc.encode(room) },
    base, { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}

/** Seals a string. `nonce` is only for the test vector. */
export async function seal(text, key, room, nonce = null) {
  const n = nonce ?? crypto.getRandomValues(new Uint8Array(12));
  const c = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: n, additionalData: enc.encode(room) }, key, enc.encode(text)));
  return JSON.stringify({ c: b64(c), n: b64(n), v: 2 });
}

/** Opens a sealed note: the text, or null if it isn't one or doesn't open with this key and room. */
export async function open(envelope, key, room) {
  try {
    const o = JSON.parse(envelope);
    if (!o || o.v !== 2 || typeof o.n !== 'string' || typeof o.c !== 'string') return null;
    const n = unb64(o.n);
    if (n.length !== 12) return null;
    const p = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: n, additionalData: enc.encode(room) }, key, unb64(o.c));
    return dec.decode(p);
  } catch { return null; }
}

/** A random pairing secret, like the Mac's. */
export function newSecret() {
  const a = new Uint8Array(26);
  crypto.getRandomValues(a);
  return [...a].map((b) => 'abcdefghijkmnpqrstuvwxyz23456789'[b % 32]).join('');
}
