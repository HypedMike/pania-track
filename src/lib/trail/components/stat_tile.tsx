/** Labelled number used in summary grids. */
function StatTile({ label, value, large = false }: { label: string; value: string; large?: boolean }) {
  return (
    <div className="flex flex-col gap-0.5 rounded-xl border border-line bg-surface px-3.5 py-2.5">
      <span className="text-xs text-muted">{label}</span>
      <span className={`font-display font-semibold ${large ? "text-[22px]" : "text-xl"}`}>{value}</span>
    </div>
  );
}

export default StatTile;
