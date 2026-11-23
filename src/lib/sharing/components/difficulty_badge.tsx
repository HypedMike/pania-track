import { useT } from "../../../shared/i18n/i18n";
import type { Difficulty } from "../sharing_api";

// Text always names the level; the colour only reinforces it.
const STYLE: Record<Difficulty, string> = {
  easy: "bg-brand-tint text-brand-tint-ink",
  moderate: "bg-warn-tint text-warn-ink",
  hard: "bg-red-100 text-red-900 dark:bg-red-950 dark:text-red-200",
};

function DifficultyBadge({ difficulty }: { difficulty: Difficulty }) {
  const t = useT();
  return (
    <span className={`rounded-md px-2 py-0.5 text-xs font-semibold ${STYLE[difficulty]}`}>
      {t(`difficulty.${difficulty}`)}
    </span>
  );
}

export default DifficultyBadge;
