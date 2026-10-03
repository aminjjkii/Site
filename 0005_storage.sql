-- =====================================================================
-- ShopYar | 0005_storage.sql
-- Bucketها و سیاست‌های Storage. بعد از 0004 اجرا می‌شود.
-- خواندن فایل‌ها عمومی است (آدرس مستقیم)، نوشتن فقط در پوشهٔ خود کاربر:
--   <user_id>/<uuid>.<jpg|jpeg|png|webp>
-- نام فایل UUID است (بدون برخورد) و پسوند محدود است. SVG عمداً مجاز نیست (XSS).
-- حجم و نوع فایل در خود bucket اعمال می‌شود. بررسی ابعاد تصویر و فشرده‌سازی
-- در کلاینت انجام می‌شود (Storage ابعاد را بررسی نمی‌کند).
-- =====================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('avatars', 'avatars', true, 2097152, array['image/jpeg', 'image/png', 'image/webp']),
  ('shop-logos', 'shop-logos', true, 2097152, array['image/jpeg', 'image/png', 'image/webp']),
  ('product-images', 'product-images', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create policy shopyar_images_insert_own on storage.objects for insert to authenticated
  with check (
    bucket_id in ('avatars', 'shop-logos', 'product-images')
    and name ~ ('^' || (select auth.uid())::text
                || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png|webp)$')
    and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and not p.is_blocked)
  );

create policy shopyar_images_select_own on storage.objects for select to authenticated
  using (
    bucket_id in ('avatars', 'shop-logos', 'product-images')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy shopyar_images_update_own on storage.objects for update to authenticated
  using (
    bucket_id in ('avatars', 'shop-logos', 'product-images')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id in ('avatars', 'shop-logos', 'product-images')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy shopyar_images_delete_own on storage.objects for delete to authenticated
  using (
    bucket_id in ('avatars', 'shop-logos', 'product-images')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
