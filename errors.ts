// خطای قابل‌نمایش به کاربر: همیشه پیام فارسی دارد و هرگز خطای خام نشان داده نمی‌شود.
export class AppError extends Error {
  readonly code: string

  constructor(code: string, message: string) {
    super(message)
    this.name = 'AppError'
    this.code = code
  }
}

const MESSAGES: Record<string, string> = {
  // ورود و ثبت‌نام
  invalid_credentials: 'ایمیل یا رمز عبور اشتباه است.',
  email_not_confirmed: 'ایمیلت هنوز تأیید نشده. لینک تأیید را در ایمیلت باز کن.',
  user_already_exists: 'این ایمیل قبلاً ثبت‌نام کرده. وارد شو یا رمز را بازیابی کن.',
  weak_password: 'رمز عبور ضعیف است. رمز طولانی‌تر با ترکیب حرف و عدد انتخاب کن.',
  same_password: 'رمز جدید باید با رمز قبلی فرق داشته باشد.',
  over_email_send_rate_limit: 'تعداد ایمیل‌های ارسالی زیاد شده. چند دقیقه بعد دوباره امتحان کن.',
  over_request_rate_limit: 'درخواست‌ها زیاد است. کمی صبر کن و دوباره امتحان کن.',
  email_address_invalid: 'این ایمیل پذیرفته نمی‌شود. ایمیل دیگری امتحان کن.',
  signup_disabled: 'ثبت‌نام فعلاً غیرفعال است.',
  session_not_found: 'نشست تو منقضی شده. دوباره وارد شو.',
  user_banned: 'حساب تو مسدود شده است.',
  // شبکه و عمومی
  network_error: 'اتصال به سرور برقرار نشد. اینترنتت را بررسی کن و دوباره امتحان کن.',
  forbidden: 'اجازهٔ این کار را نداری.',
  duplicate: 'این مقدار قبلاً استفاده شده است.',
  // خطاهای توابع دیتابیس (Phase 2)
  rate_limited: 'درخواست‌ها زیاد است. کمی بعد دوباره امتحان کن.',
  shop_not_found: 'فروشگاه پیدا نشد.',
  invalid_name: 'نام را درست وارد کن (حداقل ۲ حرف).',
  invalid_phone: 'شمارهٔ موبایل معتبر نیست (مثل 09123456789).',
  invalid_address: 'آدرس، استان یا شهر را کامل وارد کن.',
  invalid_postal_code: 'کد پستی باید ۱۰ رقم باشد.',
  invalid_note: 'توضیحات خیلی طولانی است.',
  invalid_payment_method: 'روش پرداخت معتبر نیست.',
  invalid_items: 'سبد خرید معتبر نیست.',
  product_unavailable: 'یکی از محصولات دیگر موجود نیست.',
  variant_required: 'برای این محصول رنگ یا سایز را انتخاب کن.',
  insufficient_stock: 'موجودی یکی از محصولات کافی نیست.',
  coupon_not_found: 'این کد تخفیف وجود ندارد.',
  coupon_inactive: 'این کد تخفیف فعال نیست.',
  coupon_expired: 'این کد تخفیف منقضی شده است.',
  coupon_exhausted: 'ظرفیت این کد تخفیف تمام شده است.',
  coupon_min_order: 'مبلغ سفارش به حداقل لازم برای این کد تخفیف نرسیده.',
  payment_method_unavailable: 'این روش پرداخت برای این فروشگاه فعال نیست.',
  shop_order_limit_reached: 'این فروشگاه فعلاً سفارش جدید نمی‌پذیرد.',
  order_not_found: 'سفارشی با این مشخصات پیدا نشد.',
  payment_not_pending: 'پرداخت این سفارش در انتظار تأیید نیست.',
  payment_not_paid: 'این سفارش پرداخت‌شده نیست.',
  order_cancelled: 'این سفارش لغو شده است.',
  order_not_cancelled: 'فقط سفارش لغوشده را می‌شود بازپرداخت ثبت کرد.',
  invalid_receipt: 'شمارهٔ پیگیری واریز را درست وارد کن.',
  invalid_report: 'اطلاعات گزارش معتبر نیست.',
  plan_product_limit: 'به سقف تعداد محصولات پلن رسیده‌ای. برای افزودن بیشتر، پلن را ارتقا بده.',
  plan_coupons_not_allowed: 'کد تخفیف در پلن رایگان فعال نیست. پلن را ارتقا بده.',
  image_limit: 'هر محصول حداکثر ۸ عکس دارد.',
  order_status_final: 'وضعیت این سفارش نهایی شده و قابل تغییر نیست.',
  order_status_backward: 'وضعیت سفارش را نمی‌شود به مرحلهٔ قبل برگرداند.',
  shop_id_immutable: 'این تغییر مجاز نیست.',
  unknown: 'مشکلی پیش آمد. دوباره امتحان کن.',
}

// پیام‌های انگلیسی قدیمی Supabase که کد ندارند
const ALIASES: Record<string, string> = {
  'Invalid login credentials': 'invalid_credentials',
  'Email not confirmed': 'email_not_confirmed',
  'User already registered': 'user_already_exists',
  'New password should be different from the old password.': 'same_password',
}

const NETWORK_PATTERN = /failed to fetch|networkerror|load failed|network request failed/i

export function messageFor(code: string): string {
  return MESSAGES[code] ?? MESSAGES.unknown
}

export function toAppError(e: unknown): AppError {
  if (e instanceof AppError) return e

  // فقط برای توسعه‌دهنده: خطای خام در کنسول، نه در صفحه
  console.error('[ShopYar]', e)

  const err = (typeof e === 'object' && e !== null ? e : {}) as { code?: unknown; message?: unknown }
  const code = typeof err.code === 'string' ? err.code : ''
  const message = typeof err.message === 'string' ? err.message : ''

  if (code && code in MESSAGES) return new AppError(code, MESSAGES[code])
  if (message && message in MESSAGES) return new AppError(message, MESSAGES[message])
  if (message in ALIASES) return new AppError(ALIASES[message], MESSAGES[ALIASES[message]])
  if (NETWORK_PATTERN.test(message)) return new AppError('network_error', MESSAGES.network_error)
  if (code === '23505') return new AppError('duplicate', MESSAGES.duplicate)
  if (code === '42501') return new AppError('forbidden', MESSAGES.forbidden)
  return new AppError('unknown', MESSAGES.unknown)
}
