import { Button } from './Button'

interface ErrorStateProps {
  message?: string
  onRetry?: () => void
}

export function ErrorState({ message = 'مشکلی پیش آمد. دوباره امتحان کن.', onRetry }: ErrorStateProps) {
  return (
    <div className="grid min-h-dvh place-items-center px-6">
      <div className="max-w-sm space-y-4 text-center">
        <p className="text-base font-semibold">{message}</p>
        {onRetry && (
          <Button onClick={onRetry} variant="secondary">
            تلاش دوباره
          </Button>
        )}
      </div>
    </div>
  )
}
