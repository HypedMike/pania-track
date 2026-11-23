import { useEffect, useState } from "react";
import { useParams } from "react-router";
import { analysisApi, type TourReview } from "../../../shared/analysis/analysis_api";
import { formatDate, formatDistance } from "../../../shared/gps/trail_stats";
import { useT } from "../../../shared/i18n/i18n";
import { ROUTES, trailDetailPath } from "../../../shared/router/routes";
import { useNavigation } from "../../../shared/router/use_navigation";
import PageHeader from "../../../shared/ui/layout/page_header";
import BarChart from "../../analysis/components/bar_chart";
import { BUTTON, Card, Figure } from "../../analysis/components/card";
import { formatDelta, formatSeconds } from "../../analysis/format";
import type { Trail } from "../../trail/interfaces/trail";
import { trailRepository } from "../../trail/repositories/trail_repository";
import { tourRunRepository, type TourRun } from "../tour_run_repository";

function TourReviewView() {
  const t = useT();
  const { id = "" } = useParams();
  const { goTo, goBack } = useNavigation();
  const [run, setRun] = useState<TourRun | null>(null);
  const [trail, setTrail] = useState<Trail | null>(null);
  const [review, setReview] = useState<TourReview | null | undefined>(undefined);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    (async () => {
      const r = await tourRunRepository.get(id);
      if (!r) throw new Error(t("review.notFound"));
      const [tr, fixes] = await Promise.all([trailRepository.getById(r.trailId), tourRunRepository.getFixes(id)]);
      if (!tr) throw new Error(t("error.trailNotFound"));
      const result = await analysisApi.reviewTour(tr.coordinates, fixes, { speedMs: r.plannedSpeedMs, profile: r.planProfile });
      if (alive) {
        setRun(r);
        setTrail(tr);
        setReview(result);
      }
    })().catch((e) => alive && setError(e instanceof Error ? e.message : String(e)));
    return () => {
      alive = false;
    };
  }, [id, t]);

  async function remove() {
    if (!window.confirm(t("review.confirmDelete"))) return;
    await tourRunRepository.remove(id);
    if (trail) goTo(trailDetailPath(trail.id), { replace: true });
    else goTo(ROUTES.home, { replace: true });
  }

  const header = <PageHeader onBack={goBack} backLabel={t("detail.trails")} />;
  if (error) {
    return (
      <main className="flex min-h-dvh flex-col bg-canvas">
        {header}
        <p className="p-6 text-center text-sm text-danger">{error}</p>
      </main>
    );
  }
  if (review === undefined || !run || !trail) {
    return (
      <main className="flex min-h-dvh flex-col bg-canvas">
        {header}
        <p className="p-6 text-center text-sm text-muted">{t("analysis.working")}</p>
      </main>
    );
  }

  const worst = review?.worstSplit != null ? review.splits[review.worstSplit] : null;
  const best = review?.bestSplit != null ? review.splits[review.bestSplit] : null;
  const range = (from: number, to: number) => `${formatDistance(from)} → ${formatDistance(to)}`;

  return (
    <main className="flex min-h-dvh flex-col bg-canvas">
      {header}
      <div className="flex flex-col gap-3.5 px-5 pt-4 pb-8">
        <header className="flex flex-col gap-1">
          <h1 className="font-display text-[26px] leading-tight font-bold tracking-tight">{t("review.title")}</h1>
          <button type="button" onClick={() => goTo(trailDetailPath(trail.id))} className="text-left text-sm text-brand-fg">
            {trail.name} · {formatDate(run.startedAt)}
          </button>
        </header>

        {!review ? (
          <p className="text-sm text-muted">{t("review.tooShort")}</p>
        ) : (
          <>
            <Card title={t("review.summary")} aside={review.completed ? t("review.completed") : t("review.partial", { d: formatDistance(review.coveredM) })}>
              <div className="grid grid-cols-3 gap-2">
                <Figure label={t("review.planned")} value={formatSeconds(review.plannedS)} hint={run.planProfile ? t("review.planSlope") : t("review.planFlat")} />
                <Figure label={t("review.actual")} value={formatSeconds(review.actualS)} />
                <Figure label={t("review.difference")} value={formatDelta(review.deltaS)} />
              </div>
              <p className="text-sm text-ink-soft">{summarySentence(review, t)}</p>
              <div className="grid grid-cols-3 gap-2">
                <Figure label={t("analysis.moving")} value={formatSeconds(review.movingS)} />
                <Figure label={t("analysis.stopped")} value={formatSeconds(review.stoppedS)} />
                <Figure label={t("review.offTrail")} value={formatSeconds(review.offTrailS)} />
              </div>
            </Card>

            <Card title={t("review.bySplit")} aside={t("review.splitAxis")}>
              <BarChart
                values={review.splits.map((s) => s.deltaS / 60)}
                labels={review.splits.map((s) => String(Math.round(s.toM / 100) / 10))}
                labelEvery={Math.max(1, Math.ceil(review.splits.length / 8))}
                tones={review.splits.map((s) => (s.deltaS > 30 ? "bad" : s.deltaS < -30 ? "good" : "muted"))}
                height={110}
                ariaLabel={t("review.splitsAlt")}
              />
              {worst && (
                <p className="text-sm text-ink-soft">
                  {t("review.worst", { range: range(worst.fromM, worst.toM), d: formatDelta(worst.deltaS) })}
                </p>
              )}
              {best && (
                <p className="text-sm text-ink-soft">
                  {t("review.best", { range: range(best.fromM, best.toM), d: formatDelta(best.deltaS) })}
                </p>
              )}
              <ul className="flex flex-col divide-y divide-line">
                {review.splits.map((s, i) => (
                  <li key={i} className="flex items-center justify-between gap-3 py-2 text-sm">
                    <span className="flex flex-col">
                      <span className="font-semibold">{range(s.fromM, s.toM)}</span>
                      <span className="text-xs text-muted">
                        {t("review.plannedActual", { p: formatSeconds(s.plannedS), a: formatSeconds(s.actualS) })}
                        {s.stoppedS >= 60 ? ` · ${t("review.stopIn", { d: formatSeconds(s.stoppedS) })}` : ""}
                      </span>
                    </span>
                    <span className="text-right">
                      <span className={`block font-semibold ${s.deltaS > 30 ? "text-danger" : s.deltaS < -30 ? "text-brand-fg" : ""}`}>
                        {formatDelta(s.deltaS)}
                      </span>
                      <span className="block text-xs text-muted">{formatDelta(s.cumulativeDeltaS)}</span>
                    </span>
                  </li>
                ))}
              </ul>
            </Card>
          </>
        )}

        <button type="button" className={BUTTON} onClick={() => void remove()}>
          {t("review.delete")}
        </button>
      </div>
    </main>
  );
}

function summarySentence(r: TourReview, t: ReturnType<typeof useT>): string {
  if (Math.abs(r.deltaS) < 120) return t("review.onPlan");
  const d = formatSeconds(Math.abs(r.deltaS));
  return r.deltaS > 0 ? t("review.behind", { d }) : t("review.ahead", { d });
}

export default TourReviewView;
