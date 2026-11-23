import { bytesToHex, hexToBytes } from "nostr-tools/utils";
import { decode, nsecEncode, npubEncode } from "nostr-tools/nip19";
import { generateSecretKey, getPublicKey } from "nostr-tools/pure";

/** A Nostr identity: the secret key (`nsec`) signs, the public key (`npub`) is the account id. */
export interface NostrKeys {
  nsec: string;
  npub: string;
  /** Public key as 64 hex characters, the form used inside events. */
  pubkeyHex: string;
}

function fromSecretBytes(secret: Uint8Array): NostrKeys {
  const pubkeyHex = getPublicKey(secret);
  return { nsec: nsecEncode(secret), npub: npubEncode(pubkeyHex), pubkeyHex };
}

/** Creates a brand-new random key pair. */
export function generateKeys(): NostrKeys {
  return fromSecretBytes(generateSecretKey());
}

/** Accepts an `nsec1…` string or 64 hex characters. Throws if it is neither. */
export function parseSecretKey(input: string): NostrKeys {
  const value = input.trim();
  if (/^[0-9a-f]{64}$/i.test(value)) return fromSecretBytes(hexToBytes(value.toLowerCase()));
  const decoded = decode(value);
  if (decoded.type !== "nsec") throw new Error("Not a secret key");
  return fromSecretBytes(decoded.data);
}

/** Public key of a stored `nsec`, as `npub`. */
export function npubFromNsec(nsec: string): string {
  return parseSecretKey(nsec).npub;
}

/** `npub1x8f3…k2q9`, for places where the full key does not fit. */
export function shortNpub(npub: string): string {
  return npub.length > 16 ? `${npub.slice(0, 10)}…${npub.slice(-4)}` : npub;
}

export { bytesToHex };
