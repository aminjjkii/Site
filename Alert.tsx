import type { ReactNode } from 'react'
import { cn } from '@/lib/cn'

type Variant = 'error' | 'success' | 'info'

const STYLES: Record<Variant, string> = {
  error: 'border-danger/30 bg-danger/10 text-danger',
  success: 'border-success/30 bg-success/10 text-success',
  info: 'border-brand/20 bg-brand/10 text-ink',
}

export function Alert({ variant = 'error', children }: { variant?: Variant; children: ReactNode }) {
  return (
    <div role={variant === 'error' ? 'alert' : 'status'} className={cn('rounded-xl border px-4 py-3 text-sm', STYLES[variant])}>
      {children}
    </div>
  )
}
