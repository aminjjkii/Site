import { supabase } from '@/lib/supabase'
import { toAppError } from '@/lib/errors'
import type { ShopSummary } from '@/types/database'

export async function getMyShop(ownerId: string): Promise<ShopSummary | null> {
  const { data, error } = await supabase
    .from('shops')
    .select('id, username, name, status')
    .eq('owner_id', ownerId)
    .maybeSingle()
  if (error) throw toAppError(error)
  return data as ShopSummary | null
}
