import { supabase } from '@/lib/supabase'
import { toAppError } from '@/lib/errors'
import type { Profile } from '@/types/database'

export async function getProfile(userId: string): Promise<Profile> {
  const { data, error } = await supabase
    .from('profiles')
    .select('id, full_name, phone, role, is_blocked, created_at')
    .eq('id', userId)
    .single()
  if (error) throw toAppError(error)
  return data as Profile
}
