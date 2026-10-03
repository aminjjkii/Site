// نوع‌های دستی و حداقلی. بعداً با `supabase gen types typescript` جایگزین می‌شود.
export type Role = 'seller' | 'admin'

export interface Profile {
  id: string
  full_name: string | null
  phone: string | null
  role: Role
  is_blocked: boolean
  created_at: string
}

export interface ShopSummary {
  id: string
  username: string
  name: string
  status: 'active' | 'suspended'
}
