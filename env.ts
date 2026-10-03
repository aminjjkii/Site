export const env = {
  supabaseUrl: (import.meta.env.VITE_SUPABASE_URL ?? '').trim(),
  supabaseAnonKey: (import.meta.env.VITE_SUPABASE_ANON_KEY ?? '').trim(),
} as const

export const isConfigured = env.supabaseUrl !== '' && env.supabaseAnonKey !== ''
