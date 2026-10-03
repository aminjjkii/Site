-- =====================================================================
-- ShopYar | 0002_helpers_triggers.sql
-- توابع کمکی، Triggerها، اعمال سقف پلن، همگام‌سازی موجودی و پرداخت
-- بعد از 0001 اجرا می‌شود.
-- =====================================================================

-- ---------- نرمال‌سازی ورودی ----------
-- تبدیل ارقام فارسی و عربی به انگلیسی
create or replace function private.normalize_digits(p text)
returns text
language sql
immutable
set search_path = ''
as $$
  select translate(
    coalesce(p, ''),
    U&'\06F0\06F1\06F2\06F3\06F4\06F5\06F6\06F7\06F8\06F9\0660\0661\0662\0663\0664\0665\0666\0667\0668\0669',
    '01234567890123456789'
  )
$$;

-- موبایل ایران → 09xxxxxxxxx
create or replace function private.normalize_phone(p text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  s text;
begin
  s := regexp_replace(private.normalize_digits(p), '[^0-9+]', '', 'g');
  if s like '+98%' then
    s := '0' || substr(s, 4);
  elsif s like '0098%' then
    s := '0' || substr(s, 5);
  elsif s ~ '^98[0-9]{10}$' then
    s := '0' || substr(s, 3);
  elsif s ~ '^9[0-9]{9}$' then
    s := '0' || s;
  end if;
  return s;
end
$$;

create or replace function private.normalize_postal(p text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(private.normalize_digits(p), '[^0-9]', '', 'g')
$$;

-- روز ماه شمسی (۱ تا ۳۱) برای تاریخ میلادی؛ برای «فروش این ماه» به تقویم شمسی
create or replace function private.jalali_day_of_month(p_date date)
returns int
language plpgsql
immutable
set search_path = ''
as $$
declare
  gy int := extract(year from p_date)::int;
  gm int := extract(month from p_date)::int;
  gd int := extract(day from p_date)::int;
  g_d_m int[] := array[0,31,59,90,120,151,181,212,243,273,304,334];
  gy2 int;
  days int;
begin
  gy2 := case when gm > 2 then gy + 1 else gy end;
  days := 355666 + (365 * gy) + ((gy2 + 3) / 4) - ((gy2 + 99) / 100) + ((gy2 + 399) / 400) + gd + g_d_m[gm];
  days := days % 12053;
  days := days % 1461;
  if days > 365 then
    days := (days - 1) % 365;
  end if;
  return case when days < 186 then 1 + (days % 31) else 1 + ((days - 186) % 30) end;
end
$$;

-- IP مشتری از هدر Cloudflare (قابل جعل نیست). اگر نبود null برمی‌گردد.
create or replace function private.client_ip()
returns text
language sql
stable
set search_path = ''
as $$
  select nullif(trim(nullif(current_setting('request.headers', true), '')::json ->> 'cf-connecting-ip'), '')
$$;

-- محدودیت نرخ پنجرهٔ ثابت. اگر کلید خالی باشد کاری نمی‌کند.
-- توجه: با raise exception تراکنش برمی‌گردد؛ پس برای تلاش‌های ناموفقِ حساس
-- (مثل track_order) خطا نمی‌دهیم و نتیجهٔ found=false برمی‌گردانیم.
create or replace function private.rate_limit(p_bucket text, p_key text, p_max int, p_window_seconds int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_start timestamptz;
  v_hits int;
begin
  if p_key is null or p_key = '' then
    return;
  end if;
  v_start := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);
  insert into private.rate_limits as r (bucket, key, window_start, hits)
  values (p_bucket, p_key, v_start, 1)
  on conflict (bucket, key, window_start) do update set hits = r.hits + 1
  returning r.hits into v_hits;
  if v_hits > p_max then
    raise exception 'rate_limited';
  end if;
end
$$;

-- ---------- نقش‌ها و مالکیت ----------
create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
     where p.id = (select auth.uid()) and p.role = 'admin' and not p.is_blocked
  )
$$;

-- فروشگاه‌های کاربر فعلی (برای خواندن)
create or replace function private.owned_shop_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.id from public.shops s where s.owner_id = (select auth.uid())
$$;

-- فروشگاه‌هایی که کاربر می‌تواند در آن‌ها بنویسد (فعال و کاربر مسدود نیست)
create or replace function private.writable_shop_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.id
    from public.shops s
    join public.profiles p on p.id = s.owner_id
   where s.owner_id = (select auth.uid()) and s.status = 'active' and not p.is_blocked
$$;

-- پلن فعلی فروشگاه؛ اشتراک منقضی یا نبودن اشتراک = free
create or replace function private.current_plan(p_shop_id uuid)
returns public.plans
language sql
stable
security definer
set search_path = ''
as $$
  select p.*
    from public.plans p
   where p.code = coalesce(
     (select s.plan_code from public.subscriptions s
       where s.shop_id = p_shop_id and s.status = 'active'
         and (s.period_end is null or s.period_end > now())
       limit 1),
     'free')
$$;

-- ---------- Triggerهای عمومی ----------
create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end
$$;

create trigger set_updated_at before update on public.profiles for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.shops for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.shop_payment_settings for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.products for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.product_variants for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.customers for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.coupons for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.orders for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.payments for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.subscriptions for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.store_links for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.reports for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.app_settings for each row execute function private.set_updated_at();

-- جلوگیری از جابه‌جا کردن ردیف بین فروشگاه‌ها
create or replace function private.prevent_shop_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.shop_id is distinct from old.shop_id then
    raise exception 'shop_id_immutable';
  end if;
  return new;
end
$$;

create trigger prevent_shop_change before update of shop_id on public.shop_payment_settings for each row execute function private.prevent_shop_change();
create trigger prevent_shop_change before update of shop_id on public.categories for each row execute function private.prevent_shop_change();
create trigger prevent_shop_change before update of shop_id on public.products for each row execute function private.prevent_shop_change();
create trigger prevent_shop_change before update of shop_id on public.product_images for each row execute function private.prevent_shop_change();
create trigger prevent_shop_change before update of shop_id on public.product_variants for each row execute function private.prevent_shop_change();
create trigger prevent_shop_change before update of shop_id on public.customers for each row execute function private.prevent_shop_change();
create trigger prevent_shop_change before update of shop_id on public.addresses for each row execute function private.prevent_shop_change();
create trigger prevent_shop_change before update of shop_id on public.coupons for each row execute function private.prevent_shop_change();
create trigger prevent_shop_change before update of shop_id on public.orders for each row execute function private.prevent_shop_change();
create trigger prevent_shop_change before update of shop_id on public.order_items for each row execute function private.prevent_shop_change();
create trigger prevent_shop_change before update of shop_id on public.coupon_usages for each row execute function private.prevent_shop_change();
create trigger prevent_shop_change before update of shop_id on public.payments for each row execute function private.prevent_shop_change();
create trigger prevent_shop_change before update of shop_id on public.store_links for each row execute function private.prevent_shop_change();

-- ---------- ثبت‌نام: ساخت profile ----------
-- نقش همیشه seller است؛ هر مقداری در metadata نادیده گرفته می‌شود.
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name)
  values (
    new.id,
    nullif(left(btrim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), 80), '')
  )
  on conflict (id) do nothing;
  return new;
end
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- ---------- ساخت فروشگاه: اشتراک رایگان و تنظیمات پرداخت ----------
create or replace function private.on_shop_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.subscriptions (shop_id, plan_code, status, provider)
  values (new.id, 'free', 'active', 'manual');
  insert into public.shop_payment_settings (shop_id) values (new.id);
  return null;
end
$$;

create trigger on_shop_created after insert on public.shops for each row execute function private.on_shop_created();

-- ---------- اعمال سقف پلن ----------
create or replace function private.enforce_product_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plan public.plans;
  v_count int;
begin
  if tg_op = 'UPDATE' and not (old.status = 'archived' and new.status <> 'archived') then
    return new;
  end if;
  select * into v_plan from private.current_plan(new.shop_id);
  if v_plan.max_products is not null then
    select count(*) into v_count from public.products
     where shop_id = new.shop_id and status <> 'archived';
    if v_count >= v_plan.max_products then
      raise exception 'plan_product_limit';
    end if;
  end if;
  return new;
end
$$;

create trigger enforce_product_limit_ins before insert on public.products for each row execute function private.enforce_product_limit();
create trigger enforce_product_limit_upd before update of status on public.products for each row execute function private.enforce_product_limit();

create or replace function private.enforce_coupon_plan()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plan public.plans;
begin
  select * into v_plan from private.current_plan(new.shop_id);
  if not coalesce(v_plan.can_use_coupons, false) then
    raise exception 'plan_coupons_not_allowed';
  end if;
  return new;
end
$$;

create trigger enforce_coupon_plan before insert on public.coupons for each row execute function private.enforce_coupon_plan();

-- حداکثر ۸ عکس برای هر محصول
create or replace function private.enforce_image_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select count(*) from public.product_images where product_id = new.product_id) >= 8 then
    raise exception 'image_limit';
  end if;
  return new;
end
$$;

create trigger enforce_image_limit before insert on public.product_images for each row execute function private.enforce_image_limit();

-- ---------- موجودی محصول از روی Variantها ----------
create or replace function private.products_sync_stock()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.has_variants then
    new.stock := coalesce(
      (select sum(v.stock)::int from public.product_variants v
        where v.product_id = new.id and v.is_active),
      0);
  end if;
  return new;
end
$$;

create trigger products_sync_stock before update on public.products for each row execute function private.products_sync_stock();

create or replace function private.variants_sync_product()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pid uuid := coalesce(new.product_id, old.product_id);
begin
  update public.products p
     set has_variants = exists (
           select 1 from public.product_variants v
            where v.product_id = v_pid and v.is_active)
   where p.id = v_pid;
  return null;
end
$$;

create trigger variants_sync_product after insert or update or delete on public.product_variants for each row execute function private.variants_sync_product();

-- ---------- وضعیت سفارش ----------
-- فقط حرکت رو به جلو (new → ... → delivered) یا لغو. delivered و cancelled نهایی‌اند.
-- اگر auth.uid() خالی باشد (SQL Editor / service role) برای اصلاح دستی اعمال نمی‌شود.
create or replace function private.orders_before_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_flow text[] := array['new','confirmed','processing','shipped','delivered'];
begin
  if new.order_status is distinct from old.order_status and (select auth.uid()) is not null then
    if old.order_status in ('delivered','cancelled') then
      raise exception 'order_status_final';
    end if;
    if new.order_status <> 'cancelled'
       and array_position(v_flow, new.order_status) <= array_position(v_flow, old.order_status) then
      raise exception 'order_status_backward';
    end if;
  end if;
  return new;
end
$$;

create trigger orders_before_status_change before update of order_status on public.orders for each row execute function private.orders_before_status_change();

-- لغو سفارش: برگرداندن موجودی، کوپن، آمار مشتری و لغو پرداخت در انتظار
create or replace function private.orders_after_cancel()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.product_variants v
     set stock = v.stock + a.q
    from (select i.variant_id, sum(i.quantity)::int as q
            from public.order_items i
           where i.order_id = new.id and i.variant_id is not null
           group by i.variant_id) a
   where v.id = a.variant_id;

  update public.products p
     set stock = p.stock + a.plain_q,
         sales_count = greatest(p.sales_count - a.q, 0)
    from (select i.product_id,
                 sum(i.quantity)::int as q,
                 coalesce(sum(i.quantity) filter (where i.variant_id is null), 0)::int as plain_q
            from public.order_items i
           where i.order_id = new.id and i.product_id is not null
           group by i.product_id) a
   where p.id = a.product_id;

  if new.customer_id is not null then
    update public.customers
       set orders_count = greatest(orders_count - 1, 0),
           total_spent = greatest(total_spent - new.total, 0)
     where id = new.customer_id;
  end if;

  if new.coupon_id is not null then
    update public.coupons set used_count = greatest(used_count - 1, 0) where id = new.coupon_id;
    delete from public.coupon_usages where order_id = new.id;
  end if;

  update public.payments set status = 'cancelled' where order_id = new.id and status = 'pending';
  return null;
end
$$;

create trigger orders_after_cancel
  after update of order_status on public.orders
  for each row
  when (old.order_status is distinct from new.order_status and new.order_status = 'cancelled')
  execute function private.orders_after_cancel();

-- وضعیت پرداخت سفارش همیشه از جدول payments می‌آید؛ پرداخت موفق = سفارش تأیید‌شده
create or replace function private.payments_sync_order()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.orders
     set payment_status = new.status,
         order_status = case
           when new.status = 'paid' and order_status = 'new' then 'confirmed'
           else order_status
         end
   where id = new.order_id
     and (payment_status is distinct from new.status or (new.status = 'paid' and order_status = 'new'));
  return null;
end
$$;

create trigger payments_sync_order after insert or update of status on public.payments for each row execute function private.payments_sync_order();

-- ---------- لاگ تغییرات Admin ----------
create or replace function private.audit_admin_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_old jsonb := to_jsonb(old);
begin
  if v_uid is not null and private.is_admin() then
    insert into public.admin_audit_log (admin_id, action, target_type, target_id)
    values (v_uid, tg_op, tg_table_name, coalesce(v_old ->> 'id', v_old ->> 'code', v_old ->> 'key'));
  end if;
  return null;
end
$$;

create trigger audit_admin after update or delete on public.shops for each row execute function private.audit_admin_change();
create trigger audit_admin after update or delete on public.products for each row execute function private.audit_admin_change();
create trigger audit_admin after update or delete on public.reports for each row execute function private.audit_admin_change();
create trigger audit_admin after update or delete on public.plans for each row execute function private.audit_admin_change();
create trigger audit_admin after update or delete on public.app_settings for each row execute function private.audit_admin_change();

-- ---------- پاکسازی دوره‌ای ----------
-- اختیاری: اگر pg_cron را فعال کردی، هر شب اجرا کن:
-- select cron.schedule('shopyar-purge', '0 3 * * *', 'select private.purge_old_data()');
create or replace function private.purge_old_data()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from private.rate_limits where window_start < now() - interval '2 days';
  delete from public.analytics_events where created_at < now() - interval '400 days';
$$;

-- ---------- دسترسی توابع private ----------
alter default privileges in schema private revoke execute on functions from public;
revoke execute on all functions in schema private from public;
grant execute on function private.is_admin() to anon, authenticated;
grant execute on function private.owned_shop_ids() to anon, authenticated;
grant execute on function private.writable_shop_ids() to anon, authenticated;
-- در CHECK قید username استفاده می‌شود، پس نقش‌های API باید اجازهٔ اجرا داشته باشند
grant execute on function private.is_reserved_username(text) to anon, authenticated;
