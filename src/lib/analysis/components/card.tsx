import type { ReactNode } from "react";

/** A titled block of the analysis pages. */
export function Card({ title, aside, children }: { title: string; aside?: ReactNode; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-3 rounded-2xl border border-line bg-surface p-4">
      <div className="flex items-baseline justify-between gap-3">
        <h2 className="text-sm font-semibold">{title}</h2>
        {aside && <span className="text-xs text-muted">{aside}</span>}
      </div>
      {children}
    </section>
  );
}

/** A small labelled number. */
export function Figure({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className="flex min-w-0 flex-col gap-0.5">
      <span className="text-xs text-muted">{label}</span>
      <span className="font-display text-[17px] font-semibold">{value}</span>
      {hint && <span className="text-xs text-muted">{hint}</span>}
    </div>
  );
}

export const BUTTON =
  "min-h-11 rounded-xl border border-line-strong bg-surface px-4 text-sm font-semibold active:bg-canvas disabled:opacity-50";
export const BUTTON_PRIMARY =
  "min-h-11 rounded-xl bg-brand px-4 text-sm font-semibold text-white active:bg-brand-dark disabled:opacity-50";
