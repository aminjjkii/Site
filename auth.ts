import { supabase } from '@/lib/supabase'
import { AppError, messageFor, toAppError } from '@/lib/errors'

// ساختار Auth عمداً فقط به session وابسته است. برای ورود با OTP موبایل بعداً
// signInWithPhoneOtp و verifyPhoneOtp همین‌جا اضافه می‌شوند و بقیهٔ برنامه تغییری نمی‌کند.

export type SignUpResult = { status: 'signed_in' } | { status: 'confirm_email' }

export async function signUpWithEmail(input: {
  email: string
  password: string
  fullName: string
}): Promise<SignUpResult> {
  const { data, error } = await supabase.auth.signUp({
    email: input.email,
    password: input.password,
    options: {
      data: { full_name: input.fullName },
      emailRedirectTo: `${window.location.origin}/login`,
    },
  })
  if (error) throw toAppError(error)

  // ایمیل تکراری: Supabase برای جلوگیری از افشا خطا نمی‌دهد ولی identities خالی است
  if (data.user && Array.isArray(data.user.identities) && data.user.identities.length === 0) {
    throw new AppError('user_already_exists', messageFor('user_already_exists'))
  }
  return data.session ? { status: 'signed_in' } : { status: 'confirm_email' }
}

export async function signInWithEmail(email: string, password: string): Promise<void> {
  const { error } = await supabase.auth.signInWithPassword({ email, password })
  if (error) throw toAppError(error)
}

export async function signOut(): Promise<void> {
  const { error } = await supabase.auth.signOut()
  if (error) throw toAppError(error)
}

// حتی اگر ایمیل ثبت نشده باشد موفق برمی‌گردد (جلوگیری از حدس‌زدن ایمیل‌ها)
export async function requestPasswordReset(email: string): Promise<void> {
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${window.location.origin}/reset-password`,
  })
  if (error) throw toAppError(error)
}

export async function updatePassword(password: string): Promise<void> {
  const { error } = await supabase.auth.updateUser({ password })
  if (error) throw toAppError(error)
}
