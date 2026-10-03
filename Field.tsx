import { forwardRef, useId, type InputHTMLAttributes, type ReactNode } from 'react'
import { cn } from '@/lib/cn'

interface FieldProps extends InputHTMLAttributes<HTMLInputElement> {
  label: string
  error?: string
  hint?: string
  /** برای ایمیل و رمز: جهت چپ‌به‌راست */
  ltr?: boolean
  trailing?: ReactNode
}

export const Field = forwardRef<HTMLInputElement, FieldProps>(function Field(
  { label, error, hint, ltr, trailing, className, id, ...rest },
  ref,
) {
  const autoId = useId()
  const inputId = id ?? autoId
  const descId = `${inputId}-desc`
  const hasDesc = Boolean(error || hint)

  return (
    <div className="space-y-1.5">
      <label htmlFor={inputId} className="block text-sm font-semibold">
        {label}
      </label>
      <div className="relative">
        <input
          ref={ref}
          id={inputId}
          dir={ltr ? 'ltr' : undefined}
          aria-invalid={error ? true : undefined}
          aria-describedby={hasDesc ? descId : undefined}
          className={cn(
            'block min-h-12 w-full rounded-xl border bg-surface px-4 text-base outline-none transition-colors',
            'placeholder:text-muted/70 focus:border-brand focus:ring-2 focus:ring-brand/25',
            error ? 'border-danger' : 'border-line',
            ltr && 'text-left',
            trailing ? 'pe-20' : undefined,
            className,
          )}
          {...rest}
        />
        {trailing && <div className="absolute inset-y-0 end-2 flex items-center">{trailing}</div>}
      </div>
      {hasDesc && (
        <p id={descId} role={error ? 'alert' : undefined} className={cn('text-sm', error ? 'text-danger' : 'text-muted')}>
          {error ?? hint}
        </p>
      )}
    </div>
  )
})
