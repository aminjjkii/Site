import { Link, Outlet } from 'react-router-dom'
import { LogoMark } from '@/components/ui/LogoMark'

export function AuthLayout() {
  return (
    <div className="flex min-h-dvh flex-col items-center px-4 pb-8 pt-10 sm:justify-center sm:pt-8">
      <Link to="/" className="mb-8 flex items-center gap-2.5" aria-label="شاپ‌یار، صفحهٔ اصلی">
        <LogoMark className="h-10 w-10" />
        <span className="text-2xl font-extrabold">شاپ‌یار</span>
      </Link>
      <main className="w-full max-w-md rounded-3xl border border-line bg-surface p-6 sm:p-8">
        <Outlet />
      </main>
    </div>
  )
}
