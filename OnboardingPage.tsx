import { Navigate } from 'react-router-dom'
import { Button } from '@/components/ui/Button'
import { ErrorState } from '@/components/ui/ErrorState'
import { PageLoader } from '@/components/ui/PageLoader'
import { useMyShop } from '@/hooks/useMyShop'
import { usePageTitle } from '@/hooks/usePageTitle'
import { signOut } from '@/services/auth'

// جای‌نگهدار. ویزارد هفت‌مرحله‌ای ساخت فروشگاه در فاز ۴ ساخته می‌شود.
export function OnboardingPage() {
  usePageTitle('ساخت فروشگاه')
  const shop = useMyShop()

  if (shop.isPending) return <PageLoader />
  if (shop.isError) return <ErrorState onRetry={() => void shop.refetch()} />
  if (shop.data) return <Navigate to="/dashboard" replace />

  return (
    <div className="mx-auto grid min-h-dvh max-w-md place-items-center px-6">
      <div className="space-y-4 text-center">
        <h1 className="text-xl font-extrabold">حسابت ساخته شد 🎉</h1>
        <p className="text-sm leading-7 text-muted">قدم بعدی ساخت فروشگاه است. این بخش در فاز ۴ اضافه می‌شود.</p>
        <Button variant="secondary" onClick={() => void signOut()}>
          خروج
        </Button>
      </div>
    </div>
  )
}
