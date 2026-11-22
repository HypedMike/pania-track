import { useEffect, useRef, useState } from "react";
import { formatDate, formatDistance } from "../../../shared/gps/trail_stats";
import { useT } from "../../../shared/i18n/i18n";
import { ROUTES, trailDetailPath } from "../../../shared/router/routes";
import { useNavigation } from "../../../shared/router/use_navigation";
import PageHeader from "../../../shared/ui/layout/page_header";
import type { Waypoint } from "../../trail/interfaces/trail";
import { useTrailStore } from "../../trail/stores/trail_store";
import PlanMap from "../components/plan_map";
import { DifficultyChip, InfoChip, routeLine } from "../components/route_badges";
import SteepnessProfile from "../components/steepness_profile";
import type { Hazard } from "../route_analysis";
import type { RouteVariant } from "../route_planner";
import { checkpointName, usePlanStore } from "../stores/plan_store";

/** Legend swatch per variant, matching the line styles in PlanMap. */
const SWATCH: Record<RouteVariant["kind"], string> = {
  balanced: "bg-brand-fg",
  gentlest: "bg-route",
  direct: "bg-alt",
};

function HazardNote({ hazard }: { hazard: Hazard }) {
  const t = useT();
  const text =
    hazard.kind === "steep"
      ? t("variants.hazard.steep", { n: Math.round(hazard.value) })
      : t(`variants.hazard.${hazard.kind}`, { d: formatDistance(hazard.value) });
  return (
    <span className="flex items-start gap-1.5 text-[13px] text-warn-ink">
      <svg className="mt-px shrink-0" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <path d="M12 3L2 20h20z" />
        <path d="M12 10v4M12 17v.5" />
      </svg>
      {text}
    </span>
  );
}

function VariantCard({ variant, selected, onSelect }: { variant: RouteVariant; selected: boolean; onSelect: () => void }) {
  const t = useT();
  const a = variant.analysis;
  return (
    <label
      className={`flex cursor-pointer flex-col gap-2 rounded-2xl bg-surface px-3.5 py-3 ${
        selected ? "border-2 border-brand-fg" : "border border-line"
      }`}
    >
      <div className="flex items-center gap-2.5">
        <input type="radio" name="route" checked={selected} onChange={onSelect} className="size-5 accent-brand" />
        <span className={`h-1 w-4 shrink-0 rounded-full ${SWATCH[variant.kind]}`} aria-hidden="true" />
        <span className="flex-1 text-base font-semibold">
          {variant.letter} · {t(`variants.kind.${variant.kind}`)}
        </span>
        {variant.kind === "balanced" && (
          <span className="rounded-md bg-brand-tint px-2 py-0.5 text-xs font-semibold text-brand-tint-ink">
            {t("variants.recommended")}
          </span>
        )}
      </div>
      <span className="text-sm text-ink-soft">{routeLine(a)}</span>
      <div className="flex flex-wrap gap-1.5">
        <DifficultyChip difficulty={a.difficulty} />
        <InfoChip>{t("variants.maxSlope", { n: Math.round(a.maxSlopePct) })}</InfoChip>
        {a.markedShare >= 0.05 && <InfoChip>{t("variants.marked", { n: Math.round(a.markedShare * 100) })}</InfoChip>}
        {a.roadM >= 100 && <InfoChip>{t("variants.roads", { d: formatDistance(a.roadM) })}</InfoChip>}
      </div>
      {a.hazards.map((h) => (
        <HazardNote key={h.kind} hazard={h} />
      ))}
    </label>
  );
}

function RouteVariantsView() {
  const t = useT();
  const { goTo, goBack } = useNavigation();
  const { checkpoints, variants, selectedId, cursor, select, setCursor, reset } = usePlanStore();
  const createTrail = useTrailStore((s) => s.createTrail);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const saved = useRef(false);
  const selected = variants.find((v) => v.id === selectedId) ?? variants[0];

  // Opened directly (or after the plan was reset): nothing to compare.
  useEffect(() => {
    if (variants.length === 0 && !saved.current) goTo(ROUTES.plan, { replace: true });
  }, [variants.length, goTo]);
  if (!selected) return null;

  async function save() {
    if (!selected) return;
    setSaving(true);
    setError(null);
    try {
      const waypoints: Waypoint[] = checkpoints.map((c, i) => ({
        latitude: c.latitude,
        longitude: c.longitude,
        name: checkpointName(c, i, t),
      }));
      const trail = await createTrail({
        name: t("variants.defaultName", { date: formatDate(Date.now()) }),
        description: "",
        source: "planned",
        activity: "foot",
        coordinates: selected.coordinates,
        waypoints,
      });
      saved.current = true;
      goTo(trailDetailPath(trail.id), { replace: true });
      reset();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setSaving(false);
    }
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col">
      <PageHeader title={t("variants.title")} onBack={goBack} backLabel={t("variants.back")} />

      <div className="flex flex-1 flex-col gap-3 px-5 pt-3.5 pb-[calc(20px+env(safe-area-inset-bottom))]">
        <div className="h-44 overflow-hidden rounded-2xl">
          <PlanMap checkpoints={checkpoints} variants={variants} selectedId={selected.id} cursor={cursor} />
        </div>

        <SteepnessProfile coordinates={selected.coordinates} checkpoints={checkpoints} onCursor={setCursor} />

        <fieldset className="flex flex-col gap-2.5">
          <legend className="sr-only">{t("variants.legend")}</legend>
          {variants.map((v) => (
            <VariantCard key={v.id} variant={v} selected={v.id === selected.id} onSelect={() => select(v.id)} />
          ))}
        </fieldset>

        {variants.length === 1 && <p className="text-[13px] text-muted">{t("variants.onlyOne")}</p>}
        <p className="text-xs text-muted">{t("variants.attribution")}</p>
        {error && <p className="text-sm text-danger">{error}</p>}

        <button
          type="button"
          onClick={save}
          disabled={saving}
          className="mt-auto h-[54px] rounded-2xl bg-brand text-base font-semibold text-white active:bg-brand-dark disabled:opacity-50"
        >
          {saving ? t("common.saving") : t("variants.save", { letter: selected.letter })}
        </button>
      </div>
    </main>
  );
}

export default RouteVariantsView;
