import { createClient } from '@supabase/supabase-js'
import { env, isConfigured } from './env'

// اگر env تنظیم نشده باشد، برنامه صفحهٔ راهنما نشان می‌دهد (App.tsx) و این کلاینت استفاده نمی‌شود.
// flowType = implicit: لینک بازیابی رمز در هر مرورگری (حتی مرورگر داخلی اپ ایمیل) کار می‌کند.
export const supabase = createClient(
  isConfigured ? env.supabaseUrl : 'https://not-configured.invalid',
  isConfigured ? env.supabaseAnonKey : 'not-configured',
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
      flowType: 'implicit',
    },
  },
)
