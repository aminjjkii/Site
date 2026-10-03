import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { Alert } from '@/components/ui/Alert'
import { Button } from '@/components/ui/Button'
import { Field } from '@/components/ui/Field'
import { usePageTitle } from '@/hooks/usePageTitle'
import { toAppError } from '@/lib/errors'
import { forgotSchema, type ForgotValues } from '@/lib/validation'
import { requestPasswordReset } from '@/services/auth'

export function ForgotPasswordPage() {
  usePageTitle('بازیابی رمز عبور')
  const [serverError, setServerError] = useState<string | null>(null)
  const [done, setDone] = useState(false)
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<ForgotValues>({
    resolver: zodResolver(forgotSchema),
    defaultValues: { email: '' },
  })

  const onSubmit = handleSubmit(async (values) => {
    setServerError(null)
    try {
      await requestPasswordReset(values.email)
      setDone(true)
    } catch (e) {
      setServerError(toAppError(e).message)
    }
  })

  if (done) {
    return (
      <div className="space-y-4 text-center">
        <h1 className="text-xl font-extrabold">ایمیلت را چک کن</h1>
        <Alert variant="success">اگر این ایمیل ثبت‌نام کرده باشد، لینک بازیابی رمز برایش فرستاده شد.</Alert>
        <Link to="/login" className="inline-block text-sm font-semibold text-brand">
          برگشت به صفحهٔ ورود
        </Link>
      </div>
    )
  }

  return (
    <>
      <h1 className="text-xl font-extrabold">بازیابی رمز عبور</h1>
      <p className="mt-1 text-sm text-muted">ایمیلت را بنویس تا لینک تغییر رمز برایت بفرستیم.</p>

      <form onSubmit={onSubmit} noValidate className="mt-6 space-y-4">
        {serverError && <Alert>{serverError}</Alert>}
        <Field
          label="ایمیل"
          type="email"
          ltr
          autoComplete="email"
          inputMode="email"
          error={errors.email?.message}
          {...register('email')}
        />
        <Button type="submit" fullWidth loading={isSubmitting}>
          ارسال لینک بازیابی
        </Button>
      </form>

      <p className="mt-6 text-center text-sm">
        <Link to="/login" className="font-semibold text-brand">
          برگشت به صفحهٔ ورود
        </Link>
      </p>
    </>
  )
}
