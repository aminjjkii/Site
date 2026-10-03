import { Spinner } from './Spinner'

export function PageLoader() {
  return (
    <div className="grid min-h-dvh place-items-center" role="status" aria-label="در حال بارگذاری">
      <Spinner className="h-8 w-8 text-brand" />
    </div>
  )
}
