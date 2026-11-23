import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";
import { t } from "../../shared/i18n/i18n";
import { isInvalidSecretKey, nostr } from "./nostr";

/** Public part of the profile. The secret key is never in here: the Rust backend keeps it. */
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

interface ProfileState {
  profile: Profile | null;
  /** Creates a new Nostr key pair and the profile that owns it. */
  createProfile: (input: ProfileInput) => Promise<Profile>;
  /** Uses an existing `nsec` / hex secret key instead of generating one. */
  importProfile: (secret: string, input: ProfileInput) => Promise<Profile>;
  updateProfile: (input: ProfileInput) => void;
  /** Reads the secret key from secure storage, only to show it for a backup. */
  revealSecretKey: () => Promise<string | null>;
  /** Whether this device still has the key that belongs to the profile. */
  hasSecretKey: () => Promise<boolean>;
  markBackedUp: () => void;
  /** Deletes the secret key and the profile from this device. */
  removeProfile: () => Promise<void>;
}

function normalize({ name, picture }: ProfileInput): ProfileInput {
  const trimmed = name.trim();
  if (trimmed === "") throw new Error(t("profile.nameRequired"));
  return { name: trimmed, picture };
}

function newProfile(npub: string, input: ProfileInput): Profile {
  return { ...input, npub, backedUp: false, createdAt: Date.now() };
}

export const useProfileStore = create<ProfileState>()(
  persist(
    (set, get) => ({
      profile: null,

      async createProfile(input) {
        const normalized = normalize(input);
        const profile = newProfile(await nostr.createIdentity(), normalized);
        set({ profile });
        return profile;
      },

      async importProfile(secret, input) {
        const normalized = normalize(input);
        let npub: string;
        try {
          npub = await nostr.importIdentity(secret);
        } catch (e) {
          throw isInvalidSecretKey(e) ? new Error(t("profile.importInvalid")) : e;
        }
        // An imported key was backed up somewhere already, or the user would not have it.
        const imported = { ...newProfile(npub, normalized), backedUp: true };
        set({ profile: imported });
        return imported;
      },

      updateProfile(input) {
        const current = get().profile;
        if (!current) return;
        set({ profile: { ...current, ...normalize(input) } });
      },

      revealSecretKey: () => nostr.exportSecret(),

      async hasSecretKey() {
        return (await nostr.identityNpub()) !== null;
      },

      markBackedUp() {
        const current = get().profile;
        if (current) set({ profile: { ...current, backedUp: true } });
      },

      async removeProfile() {
        await nostr.removeIdentity();
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
