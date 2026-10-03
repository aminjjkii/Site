import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase'
import { getProfile } from '@/services/profile'
import { AuthContext, type AuthState } from './auth-context'

export function AuthProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient()
  const [session, setSession] = useState<Session | null>(null)
  const [initializing, setInitializing] = useState(true)

  useEffect(() => {
    let active = true

    supabase.auth
      .getSession()
      .then(({ data }) => {
        if (!active) return
        setSession(data.session)
        setInitializing(false)
      })
      .catch(() => {
        if (active) setInitializing(false)
      })

    // داخل این callback نباید await روی فراخوانی‌های دیگر Supabase بگذاریم (خطر deadlock)
    const { data } = supabase.auth.onAuthStateChange((event, next) => {
      setSession(next)
      setInitializing(false)
      if (event === 'SIGNED_OUT') queryClient.clear()
    })

    return () => {
      active = false
      data.subscription.unsubscribe()
    }
  }, [queryClient])

  const userId = session?.user.id
  const profileQuery = useQuery({
    queryKey: ['profile', userId],
    queryFn: () => getProfile(userId as string),
    enabled: Boolean(userId),
    staleTime: 5 * 60_000,
  })

  const refetch = profileQuery.refetch
  const value = useMemo<AuthState>(
    () => ({
      session,
      user: session?.user ?? null,
      profile: profileQuery.data ?? null,
      loading: initializing || (Boolean(userId) && profileQuery.isPending),
      profileError: profileQuery.isError,
      refetchProfile: () => {
        void refetch()
      },
    }),
    [session, initializing, userId, profileQuery.data, profileQuery.isPending, profileQuery.isError, refetch],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
