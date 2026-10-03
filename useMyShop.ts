import { useQuery } from '@tanstack/react-query'
import { getMyShop } from '@/services/shops'
import { useAuth } from './useAuth'

export function useMyShop() {
  const { user } = useAuth()
  const userId = user?.id
  return useQuery({
    queryKey: ['my-shop', userId],
    queryFn: () => getMyShop(userId as string),
    enabled: Boolean(userId),
  })
}
