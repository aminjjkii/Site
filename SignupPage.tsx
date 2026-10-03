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
import { signupSchema, type SignupValues } from '@/lib/validation'
import { signUpWithEmail } from '@/services/auth'

export function SignupPage() {
  usePageTitle('ساخت فروشگاه رایگان')
  const [serverError, setServerError] = useState<string | null>(null)
  const [sentTo, setSentTo] = useState<string | null>(null)
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<SignupValues>({
    resolver: zodResolver(signupSchema),
    defaultValues: { fullName: '', email: '', password: '', confirm: '' },
  })

  const onSubmit = handleSubmit(async (values) => {
    setServerError(null)
    try {
      const result = await signUpWithEmail({
        email: values.email,
        password: values.password,
        fullName: values.fullName,
      })
      // اگر تأیید ایمیل خاموش باشد کاربر مستقیم وارد می‌شود و GuestOnly او را هدایت می‌کند
      if (result.status === 'confirm_email') setSentTo(values.email)
    } catch (e) {
      setServerError(toAppError(e).message)
    }
  })

  if (sentTo) {
    return (
      <div className="space-y-4 text-center">
        <h1 className="text-xl font-extrabold">ایمیلت را چک کن</h1>
        <Alert variant="success">
          لینک تأیید به <span dir="ltr" className="font-semibold">{sentTo}</span> فرستاده شد.
        </Alert>
        <p className="text-sm text-muted">بعد از زدن لینک، برگرد و وارد شو. اگر ایمیل نرسید، پوشهٔ اسپم را هم ببین.</p>
        <Link to="/login" className="inline-block text-sm font-semibold text-brand">
          رفتن به صفحهٔ ورود
        </Link>
      </div>
    )
  }

  return (
    <>
      <h1 className="text-xl font-extrabold">ساخت فروشگاه رایگان</h1>
      <p className="mt-1 text-sm text-muted">فقط چند دقیقه طول می‌کشد.</p>

      <form onSubmit={onSubmit} noValidate className="mt-6 space-y-4">
        {serverError && <Alert>{serverError}</Alert>}
        <Field label="نام و نام خانوادگی" autoComplete="name" error={errors.fullName?.message} {...register('fullName')} />
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
          ساخت حساب
        </Button>
      </form>

      <p className="mt-6 text-center text-sm text-muted">
        قبلاً ثبت‌نام کرده‌ای؟{' '}
        <Link to="/login" className="font-semibold text-brand">
          ورود
        </Link>
      </p>
    </>
  )
}
