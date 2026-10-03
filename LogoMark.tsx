export function LogoMark({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 64 64" aria-hidden="true">
      <rect width="64" height="64" rx="16" fill="rgb(var(--c-brand))" />
      <path d="M20 26h24l-2 20a4 4 0 0 1-4 3.6H26a4 4 0 0 1-4-3.6L20 26Z" fill="#fff" />
      <path
        d="M26 26v-3a6 6 0 0 1 12 0v3"
        fill="none"
        stroke="rgb(var(--c-accent))"
        strokeWidth="3.5"
        strokeLinecap="round"
      />
    </svg>
  )
}
