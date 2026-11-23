import type { PaceModel } from "../../../shared/analysis/analysis_api";
import BarChart from "./bar_chart";

/** Speed (km/h) at each slope; the person's own data in solid colour, estimates dimmed. */
function PaceCurve({ model, ariaLabel }: { model: PaceModel; ariaLabel: string }) {
  const bins = model.bins;
  return (
    <BarChart
      values={bins.map((b) => b.speedMs * 3.6)}
      labels={bins.map((b) => `${b.gradePct > 0 ? "+" : ""}${Math.round(b.gradePct)}`)}
      labelEvery={2}
      tones={bins.map((b) => (b.measured ? "brand" : "muted"))}
      height={110}
      ariaLabel={ariaLabel}
    />
  );
}

export default PaceCurve;
