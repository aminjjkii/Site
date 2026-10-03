import { QueryClientProvider } from '@tanstack/react-query'
import { RouterProvider } from 'react-router-dom'
import { AuthProvider } from '@/components/auth/AuthProvider'
import { ConfigMissing } from '@/components/ConfigMissing'
import { ToastProvider } from '@/components/ui/Toast'
import { isConfigured } from '@/lib/env'
import { queryClient } from '@/lib/query-client'
import { router } from '@/router'

export default function App() {
  if (!isConfigured) return <ConfigMissing />
  return (
    <QueryClientProvider client={queryClient}>
      <ToastProvider>
        <AuthProvider>
          <RouterProvider router={router} />
        </AuthProvider>
      </ToastProvider>
    </QueryClientProvider>
  )
}
