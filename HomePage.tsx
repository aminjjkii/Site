import { Link } from 'react-router-dom'
import { LogoMark } from '@/components/ui/LogoMark'
import { usePageTitle } from '@/hooks/usePageTitle'

// صفحهٔ موقت. صفحهٔ اصلی کامل (Landing) در مرحلهٔ بعد ساخته می‌شود.
export function HomePage() {
  usePageTitle('فروشگاه آنلاین برای فروشنده‌های اینستاگرام')
  return (
    <div className="mx-auto flex min-h-dvh max-w-md flex-col justify-center gap-8 px-6 py-12">
      <div className="flex items-center gap-2.5">
        <LogoMark className="h-10 w-10" />
        <span className="text-2xl font-extrabold">شاپ‌یار</span>
      </div>
      <div className="space-y-3">
        <h1 className="text-3xl font-extrabold leading-snug">فروشگاه آنلاین خودت را در چند دقیقه بساز</h1>
        <p className="text-base leading-7 text-muted">
          محصولاتت را بفروش، سفارش‌ها را مدیریت کن و لینک فروشگاهت را در اینستاگرام بگذار.
        </p>
      </div>
      <div className="flex flex-col gap-3">
        <Link
          to="/signup"
          className="inline-flex min-h-12 items-center justify-center rounded-xl bg-brand px-5 text-base font-semibold text-brand-ink"
        >
          ساخت فروشگاه رایگان
        </Link>
        <Link
          to="/login"
          className="inline-flex min-h-12 items-center justify-center rounded-xl border border-line bg-surface px-5 text-base font-semibold"
        >
          ورود
        </Link>
      </div>
    </div>
  )
}
