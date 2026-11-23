import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";
import { t } from "../../shared/i18n/i18n";
import { generateKeys, parseSecretKey, type NostrKeys } from "./nostr_keys";
import { secretStore } from "./secret_store";

/** Public part of the profile. The secret key is never in here: see `secretStore`. */
export interface Profile {
  name: string;
  /** Square avatar as a data URL; stays on this device until publishing exists. */
  picture?: string;
  npub: string;
  /** Whether the user confirmed they saved the secret key. */
  backedUp: boolean;
  createdAt: number;
}

export interface ProfileInput {
  name: string;
  picture?: string;
}

const SECRET_KEY_NAME = "nostr-nsec";

interface ProfileState {
  profile: Profile | null;
  /** Creates a new Nostr key pair and the profile that owns it. */
  createProfile: (input: ProfileInput) => Promise<Profile>;
  /** Uses an existing `nsec` / hex secret key instead of generating one. */
  importProfile: (secret: string, input: ProfileInput) => Promise<Profile>;
  updateProfile: (input: ProfileInput) => void;
  /** Reads the secret key from secure storage, e.g. to show it for a backup. */
  revealSecretKey: () => Promise<string | null>;
  markBackedUp: () => void;
  /** Deletes the secret key and the profile from this device. */
  removeProfile: () => Promise<void>;
}

function normalize({ name, picture }: ProfileInput): ProfileInput {
  const trimmed = name.trim();
  if (trimmed === "") throw new Error(t("profile.nameRequired"));
  return { name: trimmed, picture };
}

async function persistKeys(keys: NostrKeys, input: ProfileInput): Promise<Profile> {
  // The secret goes first: if this fails there is no profile that points at a missing key.
  await secretStore.set(SECRET_KEY_NAME, keys.nsec);
  return { ...input, npub: keys.npub, backedUp: false, createdAt: Date.now() };
}

export const useProfileStore = create<ProfileState>()(
  persist(
    (set, get) => ({
      profile: null,

      async createProfile(input) {
        const profile = await persistKeys(generateKeys(), normalize(input));
        set({ profile });
        return profile;
      },

      async importProfile(secret, input) {
        let keys: NostrKeys;
        try {
          keys = parseSecretKey(secret);
        } catch {
          throw new Error(t("profile.importInvalid"));
        }
        const profile = await persistKeys(keys, normalize(input));
        // An imported key was backed up somewhere already, or the user would not have it.
        const imported = { ...profile, backedUp: true };
        set({ profile: imported });
        return imported;
      },

      updateProfile(input) {
        const current = get().profile;
        if (!current) return;
        set({ profile: { ...current, ...normalize(input) } });
      },

      revealSecretKey: () => secretStore.get(SECRET_KEY_NAME),

      markBackedUp() {
        const current = get().profile;
        if (current) set({ profile: { ...current, backedUp: true } });
      },

      async removeProfile() {
        await secretStore.delete(SECRET_KEY_NAME);
        set({ profile: null });
      },
    }),
    {
      name: "pania.profile",
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({ profile: state.profile }),
    },
  ),
);
