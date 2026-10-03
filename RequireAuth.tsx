import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { Button } from '@/components/ui/Button'
import { ErrorState } from '@/components/ui/ErrorState'
import { PageLoader } from '@/components/ui/PageLoader'
import { useAuth } from '@/hooks/useAuth'
import { signOut } from '@/services/auth'
import type { Role } from '@/types/database'

function BlockedScreen() {
  return (
    <div className="grid min-h-dvh place-items-center px-6">
      <div className="max-w-sm space-y-4 text-center">
        <p className="text-base font-semibold">حساب تو مسدود شده است. برای پیگیری با پشتیبانی تماس بگیر.</p>
        <Button variant="secondary" onClick={() => void signOut()}>
          خروج
        </Button>
      </div>
    </div>
  )
}

/** مسیرهای نیازمند ورود. با role می‌شود فقط یک نقش را مجاز کرد (مثلاً admin). */
export function RequireAuth({ role }: { role?: Role }) {
  const { session, profile, loading, profileError, refetchProfile } = useAuth()
  const location = useLocation()

  if (loading) return <PageLoader />
  if (!session) {
    return <Navigate to="/login" replace state={{ from: location.pathname + location.search }} />
  }
  if (profileError || !profile) {
    return <ErrorState message="بارگذاری حساب انجام نشد. اینترنتت را بررسی کن." onRetry={refetchProfile} />
  }
  if (profile.is_blocked) return <BlockedScreen />
  if (role && profile.role !== role) return <Navigate to="/dashboard" replace />
  return <Outlet />
}
