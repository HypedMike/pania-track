import { useMemo, useRef, useState, type ChangeEvent, type FormEvent } from "react";
import { currentLocale, useT } from "../../../shared/i18n/i18n";
import { useNavigation } from "../../../shared/router/use_navigation";
import { ROUTES, trailDetailPath } from "../../../shared/router/routes";
import { parseTrackFile, type ParsedTrack } from "../../../shared/gps/track_files";
import {
  computeStats,
  formatDistance,
  formatDuration,
  formatElevation,
} from "../../../shared/gps/trail_stats";
import PageHeader from "../../../shared/ui/layout/page_header";
import StatTile from "../components/stat_tile";
import TrailMap from "../components/trail_map";
import { useTrailStore } from "../stores/trail_store";

const FIELD =
  "rounded-xl border border-line-strong bg-surface px-3.5 text-base text-ink focus:border-2 focus:border-brand-fg focus:outline-none";

interface Picked {
  file: File;
  track: ParsedTrack;
}

function formatSize(bytes: number): string {
  return bytes < 1024 * 1024 ? `${Math.max(1, Math.round(bytes / 1024))} KB` : `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

function ImportTrailView() {
  const t = useT();
  const { goTo, goBack } = useNavigation();
  const createTrail = useTrailStore((state) => state.createTrail);
  const input = useRef<HTMLInputElement>(null);
  const [picked, setPicked] = useState<Picked | null>(null);
  const [name, setName] = useState("");
  const [nameFromFile, setNameFromFile] = useState(false);
  const [description, setDescription] = useState("");
  const [join, setJoin] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const segments = picked?.track.segments ?? [];
  // Segments are always previewed as one track; unjoined ones are split into separate trails on save.
  const allPoints = useMemo(() => segments.flat(), [segments]);
  const stats = useMemo(() => computeStats(allPoints), [allPoints]);

  async function handleFile(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = ""; // allow picking the same file again
    if (!file) return;
    try {
      const track = parseTrackFile(await file.text(), file.name);
      const fallback = file.name.replace(/\.[^.]+$/, "");
      setPicked({ file, track });
      setName(track.name ?? fallback);
      setNameFromFile(Boolean(track.name));
      setJoin(true);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    if (!picked) return;
    setSaving(true);
    setError(null);
    try {
      const { track } = picked;
      const parts = join || track.segments.length === 1 ? [allPoints] : track.segments;
      const created = [];
      for (const [i, coordinates] of parts.entries()) {
        created.push(
          await createTrail({
            name: parts.length > 1 ? `${name.trim()} (${i + 1})` : name,
            description,
            source: "imported",
            coordinates,
            // Waypoints belong to the file as a whole; keep them with the first trail.
            waypoints: i === 0 ? track.waypoints : [],
          }),
        );
      }
      if (created.length === 1) goTo(trailDetailPath(created[0].id), { replace: true });
      else goTo(ROUTES.home, { replace: true });
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setSaving(false);
    }
  }

  const picker = (
    <input ref={input} type="file" onChange={handleFile} className="hidden" />
  );

  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col">
      <PageHeader
        title={t("import.title")}
        onBack={goBack}
        backLabel={t("common.cancel")}
        backIcon={false}
      />

      {!picked ? (
        <div className="flex flex-1 flex-col gap-4 px-5 pt-5 pb-6">
          {picker}
          <button
            type="button"
            onClick={() => input.current?.click()}
            className="flex flex-col items-center justify-center gap-3 rounded-2xl border-2 border-dashed border-line-strong bg-surface px-6 py-14 text-center"
          >
            <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="var(--color-brand-fg)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M12 15V4M7 9l5-5 5 5" />
              <path d="M4 15v4a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-4" />
            </svg>
            <span className="text-base font-semibold">{t("import.chooseFile")}</span>
            <span className="text-sm text-muted">{t("import.fileTypes")}</span>
          </button>
          {error && <p className="text-sm text-danger">{error}</p>}
        </div>
      ) : (
        <form onSubmit={handleSubmit} className="flex flex-1 flex-col gap-3.5 px-5 pt-4 pb-6">
          {picker}
          <div className="flex items-center gap-3 rounded-[14px] border border-line bg-surface p-3">
            <div className="flex size-11 shrink-0 items-center justify-center rounded-[10px] bg-route-tint text-route-ink">
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M14 3H6a1 1 0 0 0-1 1v16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8z" />
                <path d="M14 3v5h5" />
              </svg>
            </div>
            <div className="flex min-w-0 flex-1 flex-col gap-0.5">
              <span className="truncate text-[15px] font-semibold">{picked.file.name}</span>
              <span className="text-[13px] text-muted">
                {picked.track.format} · {formatSize(picked.file.size)} · {t("common.pointsCount", { n: allPoints.length.toLocaleString(currentLocale()) })}
              </span>
            </div>
            <button type="button" onClick={() => input.current?.click()} className="h-11 px-3 text-sm font-semibold text-brand-fg">
              {t("import.change")}
            </button>
          </div>

          <div className="h-44 overflow-hidden rounded-2xl">
            <TrailMap coordinates={allPoints} waypoints={picked.track.waypoints} color="imported" />
          </div>

          <div className="grid grid-cols-3 gap-2">
            <StatTile label={t("common.distance")} value={formatDistance(stats.distanceM)} />
            <StatTile label={t("common.elevationGain")} value={formatElevation(stats.elevationGainM, true)} />
            <StatTile label={t("common.duration")} value={formatDuration(stats.durationMs)} />
          </div>

          <label className="flex flex-col gap-1.5">
            <span className="text-sm font-semibold">{t("common.name")}</span>
            <input required value={name} onChange={(e) => setName(e.target.value)} className={`${FIELD} h-12`} />
            {nameFromFile && <span className="text-xs text-muted">{t("import.fromMetadata")}</span>}
          </label>

          <label className="flex flex-col gap-1.5">
            <span className="text-sm font-semibold">{t("common.description")}</span>
            <textarea
              rows={3}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder={t("common.notesPlaceholder")}
              className={`${FIELD} resize-none py-3 text-[15px]`}
            />
          </label>

          {segments.length > 1 && (
            <label className="flex min-h-11 items-center gap-2.5 text-sm text-ink-soft">
              <input type="checkbox" checked={join} onChange={(e) => setJoin(e.target.checked)} className="size-5 accent-brand" />
              {t("import.join", { n: segments.length })}
            </label>
          )}

          {error && <p className="text-sm text-danger">{error}</p>}

          <button
            type="submit"
            disabled={saving || name.trim() === ""}
            className="mt-auto h-[54px] rounded-2xl bg-brand text-base font-semibold text-white active:bg-brand-dark disabled:opacity-50"
          >
            {saving ? t("common.saving") : segments.length > 1 && !join ? t("import.saveMany", { n: segments.length }) : t("common.saveTrail")}
          </button>
        </form>
      )}
    </main>
  );
}

export default ImportTrailView;
