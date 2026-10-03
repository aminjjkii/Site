export function ConfigMissing() {
  return (
    <div className="grid min-h-dvh place-items-center px-6">
      <div className="max-w-md space-y-3 rounded-2xl border border-line bg-surface p-6">
        <h1 className="text-lg font-extrabold">تنظیمات اتصال کامل نیست</h1>
        <p className="text-sm text-muted">
          دو متغیر زیر باید تنظیم شوند، بعد سایت را دوباره Deploy کن (یا برنامه را دوباره اجرا کن):
        </p>
        <ul className="space-y-1 text-sm" dir="ltr">
          <li><code className="rounded bg-bg px-1.5 py-0.5">VITE_SUPABASE_URL</code></li>
          <li><code className="rounded bg-bg px-1.5 py-0.5">VITE_SUPABASE_ANON_KEY</code></li>
        </ul>
        <p className="text-sm text-muted">
          در Netlify: Site configuration ← Environment variables. مقدارها را از Supabase بردار: Project Settings ← API.
        </p>
      </div>
    </div>
  )
}
