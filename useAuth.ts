import { useContext } from 'react'
import { AuthContext, type AuthState } from '@/components/auth/auth-context'

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth باید داخل AuthProvider استفاده شود')
  return ctx
}
