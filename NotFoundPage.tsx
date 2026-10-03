import { Link } from 'react-router-dom'
import { usePageTitle } from '@/hooks/usePageTitle'

export function NotFoundPage() {
  usePageTitle('صفحه پیدا نشد')
  return (
    <div className="grid min-h-dvh place-items-center px-6">
      <div className="space-y-3 text-center">
        <p className="text-5xl font-extrabold text-brand">۴۰۴</p>
        <h1 className="text-lg font-bold">این صفحه پیدا نشد</h1>
        <Link to="/" className="inline-block text-sm font-semibold text-brand">
          برگشت به صفحهٔ اصلی
        </Link>
      </div>
    </div>
  )
}
