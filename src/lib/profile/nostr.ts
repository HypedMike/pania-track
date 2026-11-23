import { invoke } from "@tauri-apps/api/core";

/** An event as the Rust side signs it. `createdAt` is in seconds and defaults to now. */
export interface UnsignedEvent {
  kind: number;
  content: string;
  tags?: string[][];
  createdAt?: number;
}

export interface SignedEvent {
  id: string;
  pubkey: string;
  created_at: number;
  kind: number;
  tags: string[][];
  content: string;
  sig: string;
}

/**
 * The Nostr identity. Key generation, bech32 encoding, signing and encryption all happen in
 * the Rust backend (`src-tauri/src/identity.rs`); the secret key stays there and is only
 * handed to the webview by `exportSecret`, for the backup screen.
 */
export const nostr = {
  /** Creates a new key pair, stores the secret, and returns the `npub`. */
  createIdentity: () => invoke<string>("nostr_create_identity"),

  /** Stores an existing `nsec1…` / hex secret key and returns its `npub`. */
  importIdentity: (secret: string) => invoke<string>("nostr_import_identity", { secret }),

  /** `npub` of the stored key, or null when this device has none. */
  identityNpub: () => invoke<string | null>("nostr_identity_npub"),

  /** The secret key as `nsec1…`, or null. Only for showing it to the user for a backup. */
  exportSecret: () => invoke<string | null>("nostr_export_secret"),

  removeIdentity: () => invoke<void>("nostr_remove_identity"),

  async signEvent(event: UnsignedEvent): Promise<SignedEvent> {
    return JSON.parse(await invoke<string>("nostr_sign_event", { event })) as SignedEvent;
  },

  /** NIP-44 encryption for `peer` (`npub1…` or hex). */
  nip44Encrypt: (peer: string, plaintext: string) => invoke<string>("nostr_nip44_encrypt", { peer, plaintext }),

  nip44Decrypt: (peer: string, payload: string) => invoke<string>("nostr_nip44_decrypt", { peer, payload }),
};

/** True when `nostr.importIdentity` failed because the text is not a secret key. */
export function isInvalidSecretKey(error: unknown): boolean {
  return String(error).startsWith("invalid secret key");
}

/** `npub1x8f3…k2q9`, for places where the full key does not fit. */
export function shortNpub(npub: string): string {
  return npub.length > 16 ? `${npub.slice(0, 10)}…${npub.slice(-4)}` : npub;
}
