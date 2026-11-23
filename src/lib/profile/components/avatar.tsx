function initials(name: string): string {
  return name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((word) => word.charAt(0).toUpperCase())
    .join("");
}

/** Round profile picture, or the name's initials when there is none. */
function Avatar({ name, picture, size }: { name: string; picture?: string; size: number }) {
  const style = { width: size, height: size };
  if (picture) {
    return <img src={picture} alt="" style={style} className="shrink-0 rounded-full object-cover" />;
  }
  return (
    <div
      aria-hidden="true"
      style={{ ...style, fontSize: size * 0.35 }}
      className="flex shrink-0 items-center justify-center rounded-full bg-brand-tint font-display font-bold text-brand-tint-ink"
    >
      {initials(name)}
    </div>
  );
}

export default Avatar;
