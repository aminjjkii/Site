import { Navigate } from 'react-router-dom'
import { Button } from '@/components/ui/Button'
import { ErrorState } from '@/components/ui/ErrorState'
import { PageLoader } from '@/components/ui/PageLoader'
import { useAuth } from '@/hooks/useAuth'
import { useMyShop } from '@/hooks/useMyShop'
import { usePageTitle } from '@/hooks/usePageTitle'
import { signOut } from '@/services/auth'

// جای‌نگهدار. داشبورد واقعی در فاز ۱۰ ساخته می‌شود.
export function DashboardPage() {
  usePageTitle('پنل فروشنده')
  const { profile } = useAuth()
  const shop = useMyShop()

  if (shop.isPending) return <PageLoader />
  if (shop.isError) return <ErrorState onRetry={() => void shop.refetch()} />
  if (!shop.data) return <Navigate to="/onboarding" replace />

  return (
    <div className="mx-auto grid min-h-dvh max-w-md place-items-center px-6">
      <div className="space-y-4 text-center">
        <h1 className="text-xl font-extrabold">سلام {profile?.full_name ?? ''}</h1>
        <p className="text-sm text-muted">فروشگاه: {shop.data.name}</p>
        <p className="text-sm text-muted">پنل کامل در فاز ۱۰ ساخته می‌شود.</p>
        <Button variant="secondary" onClick={() => void signOut()}>
          خروج
        </Button>
      </div>
    </div>
  )
}
