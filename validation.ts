import { z } from 'zod'

const DIGIT = /[0-9\u06F0-\u06F9\u0660-\u0669]/
const NON_DIGIT = /[^0-9\u06F0-\u06F9\u0660-\u0669]/

export const emailSchema = z
  .string()
  .trim()
  .toLowerCase()
  .min(1, 'ایمیل را وارد کن')
  .max(254, 'ایمیل خیلی طولانی است')
  .email('ایمیل معتبر نیست')

export const passwordSchema = z
  .string()
  .min(8, 'رمز عبور حداقل ۸ کاراکتر باشد')
  .max(72, 'رمز عبور حداکثر ۷۲ کاراکتر باشد')
  .refine((v) => DIGIT.test(v) && NON_DIGIT.test(v), 'رمز عبور باید هم عدد داشته باشد هم حرف')

export const fullNameSchema = z
  .string()
  .trim()
  .min(2, 'نام را وارد کن')
  .max(80, 'نام خیلی طولانی است')

export const loginSchema = z.object({
  email: emailSchema,
  password: z.string().min(1, 'رمز عبور را وارد کن'),
})

export const signupSchema = z
  .object({
    fullName: fullNameSchema,
    email: emailSchema,
    password: passwordSchema,
    confirm: z.string().min(1, 'تکرار رمز عبور را وارد کن'),
  })
  .refine((d) => d.password === d.confirm, {
    path: ['confirm'],
    message: 'تکرار رمز با رمز عبور یکی نیست',
  })

export const forgotSchema = z.object({ email: emailSchema })

export const resetSchema = z
  .object({
    password: passwordSchema,
    confirm: z.string().min(1, 'تکرار رمز عبور را وارد کن'),
  })
  .refine((d) => d.password === d.confirm, {
    path: ['confirm'],
    message: 'تکرار رمز با رمز عبور یکی نیست',
  })

export type LoginValues = z.infer<typeof loginSchema>
export type SignupValues = z.infer<typeof signupSchema>
export type ForgotValues = z.infer<typeof forgotSchema>
export type ResetValues = z.infer<typeof resetSchema>
