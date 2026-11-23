import { useEffect, useState } from "react";
import { toast } from "sonner";
import { useT } from "../../../shared/i18n/i18n";
import { ROUTES } from "../../../shared/router/routes";
import { useNavigation } from "../../../shared/router/use_navigation";
import BottomNav from "../../../shared/ui/layout/bottom_nav";
import MainLayout from "../../../shared/ui/layout/main_layout";
import { useTrailStore } from "../../trail/stores/trail_store";
import Avatar from "../components/avatar";
import BackupKeyDialog from "../components/backup_key_dialog";
import { shortNpub } from "../nostr_keys";
import { useProfileStore } from "../profile_store";

const CARD = "rounded-2xl border border-line bg-surface";
const ICON = {
  width: 18,
  height: 18,
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 2,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
  "aria-hidden": true,
};

function Benefit({ icon, title, text }: { icon: React.ReactNode; title: string; text: string }) {
  return (
    <li className="flex gap-3 p-3.5 not-first:border-t not-first:border-line">
      <span className="flex size-9 shrink-0 items-center justify-center rounded-[10px] bg-brand-tint text-brand-tint-ink">
        <svg {...ICON}>{icon}</svg>
      </span>
      <div className="flex flex-col gap-0.5">
        <span className="text-[15px] font-semibold">{title}</span>
        <span className="text-[13px] leading-snug text-muted">{text}</span>
      </div>
    </li>
  );
}

function EmptyProfile() {
  const t = useT();
  const { goTo } = useNavigation();
  return (
    <>
      <div className="flex flex-col items-center gap-2.5 px-2 pt-1 text-center">
        <div className="flex size-[84px] items-center justify-center rounded-full border-2 border-dashed border-line-strong text-muted">
          <svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" aria-hidden="true">
            <circle cx="12" cy="8" r="4" />
            <path d="M4 21c1-4.5 4.5-6.5 8-6.5s7 2 8 6.5" />
          </svg>
        </div>
        <h2 className="font-display text-[22px] font-semibold">{t("profile.emptyTitle")}</h2>
        <p className="text-sm leading-normal text-muted">{t("profile.emptyIntro")}</p>
      </div>

      <ul className={`${CARD} flex flex-col`}>
        <Benefit
          icon={
            <>
              <circle cx="18" cy="5" r="3" />
              <circle cx="6" cy="12" r="3" />
              <circle cx="18" cy="19" r="3" />
              <path d="M8.6 13.5l6.8 4M15.4 6.5l-6.8 4" />
            </>
          }
          title={t("profile.benefitShareTitle")}
          text={t("profile.benefitShareText")}
        />
        <Benefit
          icon={
            <>
              <circle cx="8" cy="15" r="4" />
              <path d="M11 12l9-9M17 6l3 3M15 8l2 2" />
            </>
          }
          title={t("profile.benefitKeyTitle")}
          text={t("profile.benefitKeyText")}
        />
      </ul>

      <p className="flex gap-2 text-[13px] leading-snug text-ink-soft">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className="mt-0.5 shrink-0">
          <rect x="5" y="11" width="14" height="10" rx="2" />
          <path d="M8 11V7a4 4 0 0 1 8 0v4" />
        </svg>
        {t("profile.privateByDefault")}
      </p>

      <div className="mt-auto flex flex-col gap-2">
        <button
          type="button"
          onClick={() => goTo(ROUTES.profileCreate)}
          className="flex h-[54px] items-center justify-center rounded-2xl bg-brand text-base font-semibold text-white"
        >
          {t("profile.create")}
        </button>
        <button
          type="button"
          onClick={() => goTo(ROUTES.profileImport)}
          className="h-12 text-[15px] font-semibold text-brand-fg"
        >
          {t("profile.haveKey")}
        </button>
      </div>
    </>
  );
}

function ProfileDetails() {
  const t = useT();
  const profile = useProfileStore((s) => s.profile)!;
  const removeProfile = useProfileStore((s) => s.removeProfile);
  const revealSecretKey = useProfileStore((s) => s.revealSecretKey);
  const trails = useTrailStore((s) => s.trails);
  const [backupOpen, setBackupOpen] = useState(false);
  const [confirmRemove, setConfirmRemove] = useState(false);
  const [keyMissing, setKeyMissing] = useState(false);

  // The profile record can outlive its key (app data restored on another phone): say so.
  useEffect(() => {
    let cancelled = false;
    revealSecretKey()
      .then((key) => !cancelled && setKeyMissing(key === null))
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [revealSecretKey]);

  async function copyNpub() {
    try {
      await navigator.clipboard.writeText(profile.npub);
      toast.success(t("profile.copied"));
    } catch {
      toast.error(t("profile.copyFailed"));
    }
  }

  async function remove() {
    try {
      await removeProfile();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : String(e));
    }
  }

  const stats = [
    { label: t("profile.public"), value: 0 },
    { label: t("profile.private"), value: trails.length },
  ];

  return (
    <>
      <div className={`${CARD} flex items-center gap-3.5 p-4`}>
        <Avatar name={profile.name} picture={profile.picture} size={68} />
        <div className="flex min-w-0 flex-1 flex-col gap-1">
          <span className="truncate text-[19px] font-semibold">{profile.name}</span>
          <span className="font-mono text-[13px] text-muted">{shortNpub(profile.npub)}</span>
        </div>
        <button
          type="button"
          aria-label={t("profile.copyKey")}
          onClick={copyNpub}
          className="flex size-11 shrink-0 items-center justify-center rounded-full border border-line-strong"
        >
          <svg {...ICON}>
            <rect x="9" y="9" width="11" height="11" rx="2" />
            <path d="M5 15V5a1 1 0 0 1 1-1h10" />
          </svg>
        </button>
      </div>

      {keyMissing && <p className="rounded-xl bg-warn-tint p-3 text-[13px] leading-snug text-warn-ink">{t("profile.keyMissing")}</p>}

      <div className="grid grid-cols-2 gap-2">
        {stats.map((s) => (
          <div key={s.label} className="flex flex-col gap-0.5 rounded-xl border border-line bg-surface px-3 py-2.5">
            <span className="text-xs text-muted">{s.label}</span>
            <span className="font-display text-xl font-semibold">{s.value}</span>
          </div>
        ))}
      </div>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">{t("profile.publicTrails")}</h2>
        <p className={`${CARD} p-4 text-sm text-muted`}>{t("profile.noPublicTrails")}</p>
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">{t("profile.account")}</h2>
        <div className={`${CARD} flex flex-col`}>
          <button
            type="button"
            onClick={() => setBackupOpen(true)}
            className="flex min-h-12 items-center justify-between gap-2 px-3.5 text-left text-[15px] font-medium"
          >
            {t("profile.backup")}
            <span
              className={`rounded-md px-2 py-0.5 text-xs font-semibold ${
                profile.backedUp ? "bg-brand-tint text-brand-tint-ink" : "bg-warn-tint text-warn-ink"
              }`}
            >
              {profile.backedUp ? t("profile.backupDone") : t("profile.backupNotDone")}
            </span>
          </button>
          {confirmRemove ? (
            <div className="flex flex-col gap-3 border-t border-line p-3.5">
              <p className="text-sm text-ink-soft">{t("profile.removeText")}</p>
              <div className="grid grid-cols-2 gap-2">
                <button type="button" onClick={() => setConfirmRemove(false)} className="h-11 rounded-xl border border-line-strong text-[15px] font-semibold">
                  {t("common.cancel")}
                </button>
                <button type="button" onClick={remove} className="h-11 rounded-xl bg-danger text-[15px] font-semibold text-white">
                  {t("profile.removeConfirm")}
                </button>
              </div>
            </div>
          ) : (
            <button
              type="button"
              onClick={() => setConfirmRemove(true)}
              className="flex min-h-12 items-center border-t border-line px-3.5 text-left text-[15px] font-medium text-danger"
            >
              {t("profile.remove")}
            </button>
          )}
        </div>
      </section>

      {backupOpen && <BackupKeyDialog onClose={() => setBackupOpen(false)} />}
    </>
  );
}

function ProfileView() {
  const t = useT();
  const { goTo } = useNavigation();
  const profile = useProfileStore((s) => s.profile);
  const load = useTrailStore((s) => s.load);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <div className="flex min-h-screen flex-col">
      <MainLayout
        header={
          <header className="flex items-center justify-between">
            <h1 className="font-display text-[34px] leading-tight font-bold tracking-tight">{t("profile.pageTitle")}</h1>
            {profile && (
              <button
                type="button"
                onClick={() => goTo(ROUTES.profileCreate)}
                className="h-11 rounded-full border border-line-strong bg-surface px-4 text-sm font-semibold"
              >
                {t("profile.edit")}
              </button>
            )}
          </header>
        }
        className="mx-auto flex w-full max-w-2xl flex-1 flex-col gap-4 px-5 pt-[calc(1.75rem+var(--safe-top))] pb-6"
      >
        {profile ? <ProfileDetails /> : <EmptyProfile />}
      </MainLayout>
      <BottomNav current="profile" />
    </div>
  );
}

export default ProfileView;
