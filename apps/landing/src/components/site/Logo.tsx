export function Logo({ className = "h-9 w-9" }: { className?: string }) {
  return (
    <img
      src="/portside-logo.png"
      alt="Logo do Portside"
      className={className}
      width={72}
      height={72}
    />
  );
}
