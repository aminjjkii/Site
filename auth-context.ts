import { createContext } from 'react'
import type { Session, User } from '@supabase/supabase-js'
import type { Profile } from '@/types/database'

export interface AuthState {
  session: Session | null
  user: User | null
  profile: Profile | null
  /** تا وقتی نشست و پروفایل مشخص نشده true است */
  loading: boolean
  profileError: boolean
  refetchProfile: () => void
}

export const AuthContext = createContext<AuthState | null>(null)
