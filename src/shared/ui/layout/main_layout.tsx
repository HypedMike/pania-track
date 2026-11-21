export default function MainLayout({
  header,
  children,
  className,
}: {
  header?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <main className={className}>
      {header}
      {children}
    </main>
  );
}
