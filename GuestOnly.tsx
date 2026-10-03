import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { PageLoader } from '@/components/ui/PageLoader'
import { useAuth } from '@/hooks/useAuth'

function safeTarget(from: unknown): string {
  return typeof from === 'string' && from.startsWith('/') && !from.startsWith('//') ? from : '/dashboard'
}

/** صفحه‌های ورود و ثبت‌نام: کاربر واردشده به پنل هدایت می‌شود */
export function GuestOnly() {
  const { session, loading } = useAuth()
  const location = useLocation()

  if (loading) return <PageLoader />
  if (session) {
    const from = (location.state as { from?: unknown } | null)?.from
    return <Navigate to={safeTarget(from)} replace />
  }
  return <Outlet />
}
