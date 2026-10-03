-- =====================================================================
-- ShopYar | 0004_rls.sql
-- دسترسی‌ها (GRANT) و سیاست‌های RLS. بعد از 0003 اجرا می‌شود.
-- اصل: همه چیز پیش‌فرض ممنوع؛ فقط آنچه لازم است باز می‌شود.
-- مشتری مهمان مستقیم روی هیچ جدولی نمی‌نویسد (فقط RPCها).
-- =====================================================================

-- ---------- خط پایه: همه‌چیز بسته ----------
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

alter table public.plans enable row level security;
alter table public.profiles enable row level security;
alter table public.shops enable row level security;
alter table public.shop_payment_settings enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.product_images enable row level security;
alter table public.product_variants enable row level security;
alter table public.customers enable row level security;
alter table public.addresses enable row level security;
alter table public.coupons enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.coupon_usages enable row level security;
alter table public.payments enable row level security;
alter table public.subscriptions enable row level security;
alter table public.analytics_events enable row level security;
alter table public.store_links enable row level security;
alter table public.reports enable row level security;
alter table public.admin_audit_log enable row level security;
alter table public.app_settings enable row level security;

-- ---------- plans ----------
grant select on public.plans to anon, authenticated;
grant insert, update on public.plans to authenticated;
create policy plans_select_public on public.plans for select to anon, authenticated
  using (is_active);
create policy plans_admin_write on public.plans for all to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

-- ---------- app_settings (عمومی، فقط Admin می‌نویسد) ----------
grant select on public.app_settings to anon, authenticated;
grant insert, update on public.app_settings to authenticated;
create policy app_settings_select_public on public.app_settings for select to anon, authenticated
  using (true);
create policy app_settings_admin_write on public.app_settings for all to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

-- ---------- profiles: نقش و مسدودی را کاربر نمی‌تواند عوض کند ----------
grant select on public.profiles to authenticated;
grant update (full_name, phone) on public.profiles to authenticated;
create policy profiles_select_own on public.profiles for select to authenticated
  using (id = (select auth.uid()));
create policy profiles_select_admin on public.profiles for select to authenticated
  using ((select private.is_admin()));
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- ---------- shops ----------
grant select on public.shops to anon, authenticated;
grant insert (owner_id, username, name, description, category, logo_path, instagram, whatsapp, telegram, phone)
  on public.shops to authenticated;
grant update (username, name, description, category, logo_path, instagram, whatsapp, telegram, phone,
              shipping_fee, free_shipping_over)
  on public.shops to authenticated;
create policy shops_select_active on public.shops for select to anon, authenticated
  using (status = 'active');
create policy shops_select_own on public.shops for select to authenticated
  using (owner_id = (select auth.uid()));
create policy shops_select_admin on public.shops for select to authenticated
  using ((select private.is_admin()));
create policy shops_insert_own on public.shops for insert to authenticated
  with check (
    owner_id = (select auth.uid())
    and not exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.is_blocked)
  );
create policy shops_update_own on public.shops for update to authenticated
  using (id in (select private.writable_shop_ids()))
  with check (owner_id = (select auth.uid()));

-- ---------- shop_payment_settings (فقط مالک و Admin) ----------
grant select on public.shop_payment_settings to authenticated;
grant update (card_enabled, card_number, card_holder, online_provider, zarinpal_merchant_id)
  on public.shop_payment_settings to authenticated;
create policy sps_select_owner on public.shop_payment_settings for select to authenticated
  using (shop_id in (select private.owned_shop_ids()));
create policy sps_select_admin on public.shop_payment_settings for select to authenticated
  using ((select private.is_admin()));
create policy sps_update_owner on public.shop_payment_settings for update to authenticated
  using (shop_id in (select private.writable_shop_ids()))
  with check (shop_id in (select private.writable_shop_ids()));

-- ---------- categories ----------
grant select on public.categories to anon, authenticated;
grant insert (shop_id, name, slug, sort_order) on public.categories to authenticated;
grant update (name, slug, sort_order) on public.categories to authenticated;
grant delete on public.categories to authenticated;
create policy categories_select_public on public.categories for select to anon, authenticated
  using (exists (select 1 from public.shops s where s.id = categories.shop_id and s.status = 'active'));
create policy categories_select_admin on public.categories for select to authenticated
  using ((select private.is_admin()));
create policy categories_write_owner on public.categories for all to authenticated
  using (shop_id in (select private.writable_shop_ids()))
  with check (shop_id in (select private.writable_shop_ids()));

-- ---------- products (sales_count و has_variants فقط توسط سرور تغییر می‌کند) ----------
grant select on public.products to anon, authenticated;
grant insert (shop_id, category_id, title, description, price, discount_price, stock, sku, status, featured)
  on public.products to authenticated;
grant update (category_id, title, description, price, discount_price, stock, sku, status, featured)
  on public.products to authenticated;
grant delete on public.products to authenticated;
create policy products_select_public on public.products for select to anon, authenticated
  using (
    status = 'active'
    and exists (select 1 from public.shops s where s.id = products.shop_id and s.status = 'active')
  );
create policy products_select_admin on public.products for select to authenticated
  using ((select private.is_admin()));
create policy products_write_owner on public.products for all to authenticated
  using (shop_id in (select private.writable_shop_ids()))
  with check (shop_id in (select private.writable_shop_ids()));
create policy products_admin_update on public.products for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));
create policy products_admin_delete on public.products for delete to authenticated
  using ((select private.is_admin()));

-- ---------- product_images ----------
grant select on public.product_images to anon, authenticated;
grant insert (product_id, shop_id, path, alt, sort_order) on public.product_images to authenticated;
grant update (alt, sort_order) on public.product_images to authenticated;
grant delete on public.product_images to authenticated;
create policy product_images_select_public on public.product_images for select to anon, authenticated
  using (exists (
    select 1 from public.products p
      join public.shops s on s.id = p.shop_id
     where p.id = product_images.product_id and p.status = 'active' and s.status = 'active'
  ));
create policy product_images_select_admin on public.product_images for select to authenticated
  using ((select private.is_admin()));
create policy product_images_write_owner on public.product_images for all to authenticated
  using (shop_id in (select private.writable_shop_ids()))
  with check (shop_id in (select private.writable_shop_ids()));

-- ---------- product_variants ----------
grant select on public.product_variants to anon, authenticated;
grant insert (product_id, shop_id, attributes, sku, stock, price_override, sort_order, is_active)
  on public.product_variants to authenticated;
grant update (attributes, sku, stock, price_override, sort_order, is_active)
  on public.product_variants to authenticated;
grant delete on public.product_variants to authenticated;
create policy product_variants_select_public on public.product_variants for select to anon, authenticated
  using (
    is_active
    and exists (
      select 1 from public.products p
        join public.shops s on s.id = p.shop_id
       where p.id = product_variants.product_id and p.status = 'active' and s.status = 'active'
    )
  );
create policy product_variants_select_admin on public.product_variants for select to authenticated
  using ((select private.is_admin()));
create policy product_variants_write_owner on public.product_variants for all to authenticated
  using (shop_id in (select private.writable_shop_ids()))
  with check (shop_id in (select private.writable_shop_ids()));

-- ---------- store_links ----------
grant select on public.store_links to anon, authenticated;
grant insert (shop_id, type, label, url, sort_order, is_active) on public.store_links to authenticated;
grant update (type, label, url, sort_order, is_active) on public.store_links to authenticated;
grant delete on public.store_links to authenticated;
create policy store_links_select_public on public.store_links for select to anon, authenticated
  using (
    is_active
    and exists (select 1 from public.shops s where s.id = store_links.shop_id and s.status = 'active')
  );
create policy store_links_select_admin on public.store_links for select to authenticated
  using ((select private.is_admin()));
create policy store_links_write_owner on public.store_links for all to authenticated
  using (shop_id in (select private.writable_shop_ids()))
  with check (shop_id in (select private.writable_shop_ids()));

-- ---------- coupons (عمومی نیست؛ مشتری از validate_coupon استفاده می‌کند) ----------
grant select on public.coupons to authenticated;
grant insert (shop_id, code, discount_type, discount_value, minimum_order, maximum_discount, expires_at, usage_limit, active)
  on public.coupons to authenticated;
grant update (code, discount_type, discount_value, minimum_order, maximum_discount, expires_at, usage_limit, active)
  on public.coupons to authenticated;
grant delete on public.coupons to authenticated;
create policy coupons_select_admin on public.coupons for select to authenticated
  using ((select private.is_admin()));
create policy coupons_write_owner on public.coupons for all to authenticated
  using (shop_id in (select private.writable_shop_ids()))
  with check (shop_id in (select private.writable_shop_ids()));

-- ---------- جدول‌های فقط‌خواندنی برای مالک و Admin ----------
-- نوشتن فقط از طریق RPC و Triggerهای سمت سرور
grant select on public.customers, public.addresses, public.order_items, public.coupon_usages,
                public.payments, public.subscriptions to authenticated;

create policy customers_select_owner on public.customers for select to authenticated
  using (shop_id in (select private.owned_shop_ids()));
create policy customers_select_admin on public.customers for select to authenticated
  using ((select private.is_admin()));

create policy addresses_select_owner on public.addresses for select to authenticated
  using (shop_id in (select private.owned_shop_ids()));
create policy addresses_select_admin on public.addresses for select to authenticated
  using ((select private.is_admin()));

create policy order_items_select_owner on public.order_items for select to authenticated
  using (shop_id in (select private.owned_shop_ids()));
create policy order_items_select_admin on public.order_items for select to authenticated
  using ((select private.is_admin()));

create policy coupon_usages_select_owner on public.coupon_usages for select to authenticated
  using (shop_id in (select private.owned_shop_ids()));
create policy coupon_usages_select_admin on public.coupon_usages for select to authenticated
  using ((select private.is_admin()));

create policy payments_select_owner on public.payments for select to authenticated
  using (shop_id in (select private.owned_shop_ids()));
create policy payments_select_admin on public.payments for select to authenticated
  using ((select private.is_admin()));

create policy subscriptions_select_owner on public.subscriptions for select to authenticated
  using (shop_id in (select private.owned_shop_ids()));
create policy subscriptions_select_admin on public.subscriptions for select to authenticated
  using ((select private.is_admin()));

-- ---------- orders: فروشنده فقط وضعیت، یادداشت داخلی و کد رهگیری را عوض می‌کند ----------
grant select on public.orders to authenticated;
grant update (order_status, internal_note, shipping_tracking_code) on public.orders to authenticated;
create policy orders_select_owner on public.orders for select to authenticated
  using (shop_id in (select private.owned_shop_ids()));
create policy orders_select_admin on public.orders for select to authenticated
  using ((select private.is_admin()));
create policy orders_update_owner on public.orders for update to authenticated
  using (shop_id in (select private.writable_shop_ids()))
  with check (shop_id in (select private.writable_shop_ids()));

-- ---------- reports و admin_audit_log ----------
grant select on public.reports to authenticated;
grant update (status, admin_note) on public.reports to authenticated;
create policy reports_select_admin on public.reports for select to authenticated
  using ((select private.is_admin()));
create policy reports_update_admin on public.reports for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

grant select on public.admin_audit_log to authenticated;
create policy audit_select_admin on public.admin_audit_log for select to authenticated
  using ((select private.is_admin()));

-- analytics_events: عمداً بدون Policy و بدون GRANT (فقط RPC می‌نویسد، آمار از RPC خوانده می‌شود)

-- ---------- دسترسی RPCها ----------
-- عمومی (مشتری مهمان هم می‌تواند)
grant execute on function public.place_order(uuid, jsonb, text, text, text, text, text, text, text, text, text, text) to anon, authenticated;
grant execute on function public.validate_coupon(uuid, text, bigint) to anon, authenticated;
grant execute on function public.track_order(text, text) to anon, authenticated;
grant execute on function public.submit_payment_receipt(text, text, text) to anon, authenticated;
grant execute on function public.track_event(uuid, text, text, uuid) to anon, authenticated;
grant execute on function public.check_username_available(text) to anon, authenticated;
grant execute on function public.report_content(text, uuid, text, text) to anon, authenticated;
-- فقط کاربر واردشده (فروشنده / Admin)
grant execute on function public.confirm_payment(uuid) to authenticated;
grant execute on function public.mark_refunded(uuid) to authenticated;
grant execute on function public.seller_dashboard() to authenticated;
