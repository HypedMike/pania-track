import { useRef, useState, type ReactNode } from "react";

interface BottomSheetProps {
  /** Whether `children` are hidden; owned by the parent. */
  collapsed: boolean;
  onCollapsedChange: (collapsed: boolean) => void;
  /** Accessible name of the handle, describing what activating it does. */
  handleLabel: string;
  /** Always visible, right under the handle. */
  summary?: ReactNode;
  /** Hidden when collapsed. */
  children: ReactNode;
}

/**
 * Bottom drawer with a draggable handle: drag down to hide `children`, up (or tap) to show them.
 * Whether it is collapsed is controlled by the parent; only the in-flight gesture height is local.
 */
function BottomSheet({
  collapsed,
  onCollapsedChange,
  handleLabel,
  summary,
  children,
}: BottomSheetProps) {
  /** Body height while dragging or animating; null lets the body size itself. */
  const [height, setHeight] = useState<number | null>(null);
  const [dragging, setDragging] = useState(false);
  const bodyRef = useRef<HTMLDivElement>(null);
  const sectionRef = useRef<HTMLElement>(null);
  const drag = useRef<{ y: number; full: number; moved: boolean } | null>(null);

  /** Tallest the body can be while the whole sheet still fits its max-height. */
  function fullHeight() {
    const body = bodyRef.current;
    const section = sectionRef.current;
    if (!body || !section) return 0;
    const max = parseFloat(getComputedStyle(section).maxHeight);
    const room = max - (section.offsetHeight - body.offsetHeight);
    return Math.max(0, Math.min(body.scrollHeight, room || Infinity));
  }

  function onPointerDown(e: React.PointerEvent) {
    drag.current = { y: e.clientY, full: fullHeight(), moved: false };
    e.currentTarget.setPointerCapture(e.pointerId);
    setDragging(true);
  }
  function onPointerMove(e: React.PointerEvent) {
    const d = drag.current;
    if (!d) return;
    const dy = e.clientY - d.y;
    if (Math.abs(dy) > 4) d.moved = true;
    setHeight(Math.min(d.full, Math.max(0, (collapsed ? 0 : d.full) - dy)));
  }
  function onPointerEnd() {
    const d = drag.current;
    drag.current = null;
    setDragging(false);
    if (!d) return;
    const current = height ?? (collapsed ? 0 : d.full);
    const next = d.moved ? current < d.full / 2 : !collapsed;
    onCollapsedChange(next);
    // Expanded: hand sizing back to the layout (right away if nothing will animate).
    setHeight(
      next ? 0 : Math.round(current) === Math.round(d.full) ? null : d.full,
    );
  }
  function onKeyDown(e: React.KeyboardEvent) {
    if (e.key !== "ArrowDown" && e.key !== "ArrowUp") return;
    e.preventDefault();
    setHeight(null);
    onCollapsedChange(e.key === "ArrowDown");
  }

  return (
    <section
      ref={sectionRef}
      className="relative z-1000 -mt-7 flex max-h-[70dvh] shrink-0 flex-col gap-2.5 rounded-t-[28px] bg-surface px-5 pt-2.5 pb-[calc(24px+env(safe-area-inset-bottom))] shadow-[0_-4px_24px_rgb(22_32_27/0.10)]"
    >
      <div
        role="separator"
        tabIndex={0}
        aria-orientation="horizontal"
        aria-label={handleLabel}
        aria-expanded={!collapsed}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerEnd}
        onPointerCancel={onPointerEnd}
        onKeyDown={onKeyDown}
        className="-mt-2.5 flex h-8 shrink-0 cursor-grab touch-none items-center justify-center self-stretch"
      >
        <div className="h-1 w-10 rounded-full bg-line-strong" />
      </div>

      {summary}

      <div
        ref={bodyRef}
        inert={collapsed && !dragging}
        onTransitionEnd={(e) => {
          if (e.target === e.currentTarget && !collapsed && !dragging)
            setHeight(null);
        }}
        style={height === null ? undefined : { height }}
        className={`flex min-h-0 flex-col ${height === null ? "overflow-y-auto overscroll-contain" : "overflow-hidden"} ${dragging ? "" : "transition-[height] duration-200 motion-reduce:transition-none"}`}
      >
        <div className="flex shrink-0 flex-col gap-2.5">{children}</div>
      </div>
    </section>
  );
}

export default BottomSheet;
