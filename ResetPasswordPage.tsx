import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { Alert } from '@/components/ui/Alert'
import { Button } from '@/components/ui/Button'
import { PasswordField } from '@/components/ui/PasswordField'
import { Spinner } from '@/components/ui/Spinner'
import { useToast } from '@/components/ui/Toast'
import { useAuth } from '@/hooks/useAuth'
import { usePageTitle } from '@/hooks/usePageTitle'
import { toAppError } from '@/lib/errors'
import { resetSchema, type ResetValues } from '@/lib/validation'
import { updatePassword } from '@/services/auth'

export function ResetPasswordPage() {
  usePageTitle('رمز عبور جدید')
  const { session, loading } = useAuth()
  const navigate = useNavigate()
  const toast = useToast()
  const [serverError, setServerError] = useState<string | null>(null)
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<ResetValues>({
    resolver: zodResolver(resetSchema),
    defaultValues: { password: '', confirm: '' },
  })

  const onSubmit = handleSubmit(async (values) => {
    setServerError(null)
    try {
      await updatePassword(values.password)
      toast.success('رمز عبور عوض شد.')
      navigate('/dashboard', { replace: true })
    } catch (e) {
      setServerError(toAppError(e).message)
    }
  })

  if (loading) {
    return (
      <div className="grid place-items-center py-8" role="status" aria-label="در حال بررسی لینک">
        <Spinner className="h-7 w-7 text-brand" />
      </div>
    )
  }

  // لینک بازیابی نشست می‌سازد. بدون نشست یعنی لینک نامعتبر یا منقضی است.
  if (!session) {
    return (
      <div className="space-y-4 text-center">
        <h1 className="text-xl font-extrabold">لینک معتبر نیست</h1>
        <Alert>این لینک منقضی شده یا قبلاً استفاده شده. یک لینک تازه بگیر.</Alert>
        <Link to="/forgot-password" className="inline-block text-sm font-semibold text-brand">
          دریافت لینک جدید
        </Link>
      </div>
    )
  }

  return (
    <>
      <h1 className="text-xl font-extrabold">رمز عبور جدید</h1>
      <p className="mt-1 text-sm text-muted">یک رمز تازه برای حسابت انتخاب کن.</p>

      <form onSubmit={onSubmit} noValidate className="mt-6 space-y-4">
        {serverError && <Alert>{serverError}</Alert>}
        <PasswordField
          label="رمز عبور جدید"
          autoComplete="new-password"
          hint="حداقل ۸ کاراکتر، شامل حرف و عدد"
          error={errors.password?.message}
          {...register('password')}
        />
        <PasswordField
          label="تکرار رمز عبور"
          autoComplete="new-password"
          error={errors.confirm?.message}
          {...register('confirm')}
        />
        <Button type="submit" fullWidth loading={isSubmitting}>
          ذخیرهٔ رمز جدید
        </Button>
      </form>
    </>
  )
}
