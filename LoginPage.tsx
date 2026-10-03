import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { Alert } from '@/components/ui/Alert'
import { Button } from '@/components/ui/Button'
import { Field } from '@/components/ui/Field'
import { PasswordField } from '@/components/ui/PasswordField'
import { usePageTitle } from '@/hooks/usePageTitle'
import { toAppError } from '@/lib/errors'
import { loginSchema, type LoginValues } from '@/lib/validation'
import { signInWithEmail } from '@/services/auth'

export function LoginPage() {
  usePageTitle('ورود')
  const [serverError, setServerError] = useState<string | null>(null)
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<LoginValues>({
    resolver: zodResolver(loginSchema),
    defaultValues: { email: '', password: '' },
  })

  const onSubmit = handleSubmit(async (values) => {
    setServerError(null)
    try {
      // بعد از موفقیت، GuestOnly خودش کاربر را به پنل هدایت می‌کند
      await signInWithEmail(values.email, values.password)
    } catch (e) {
      setServerError(toAppError(e).message)
    }
  })

  return (
    <>
      <h1 className="text-xl font-extrabold">ورود به پنل فروشنده</h1>
      <p className="mt-1 text-sm text-muted">فروشگاه و سفارش‌هایت همین‌جاست.</p>

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
        <PasswordField
          label="رمز عبور"
          autoComplete="current-password"
          error={errors.password?.message}
          {...register('password')}
        />
        <div className="text-end">
          <Link to="/forgot-password" className="text-sm font-semibold text-brand">
            رمز را فراموش کرده‌ام
          </Link>
        </div>
        <Button type="submit" fullWidth loading={isSubmitting}>
          ورود
        </Button>
      </form>

      <p className="mt-6 text-center text-sm text-muted">
        حساب نداری؟{' '}
        <Link to="/signup" className="font-semibold text-brand">
          ساخت فروشگاه رایگان
        </Link>
      </p>
    </>
  )
}
