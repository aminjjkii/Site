-- =====================================================================
-- ShopYar | 0003_rpc.sql
-- توابع قابل‌فراخوانی از فرانت (supabase.rpc). همهٔ منطق حساس اینجاست.
-- بعد از 0002 اجرا می‌شود. دسترسی‌ها در 0004 تنظیم می‌شود.
--
-- کدهای خطا (message خطا؛ در فرانت به پیام فارسی نگاشت می‌شود):
--   rate_limited, shop_not_found, invalid_name, invalid_phone, invalid_address,
--   invalid_postal_code, invalid_note, invalid_payment_method, invalid_items,
--   product_unavailable, variant_required, insufficient_stock, coupon_not_found,
--   coupon_inactive, coupon_expired, coupon_exhausted, coupon_min_order,
--   payment_method_unavailable, shop_order_limit_reached, order_not_found,
--   payment_not_pending, payment_not_paid, order_cancelled, order_not_cancelled,
--   invalid_receipt, invalid_report, plan_product_limit, plan_coupons_not_allowed,
--   image_limit, order_status_final, order_status_backward, shop_id_immutable
-- =====================================================================

-- ---------- محاسبهٔ کوپن (داخلی؛ هم در validate_coupon هم در place_order) ----------
create or replace function private.evaluate_coupon(p_shop_id uuid, p_code text, p_subtotal bigint, p_lock boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.coupons;
  v_plan public.plans;
  v_code text := upper(btrim(coalesce(p_code, '')));
  v_disc bigint;
begin
  if v_code = '' then
    return jsonb_build_object('coupon_id', null, 'discount', 0, 'error', null);
  end if;

  if p_lock then
    select * into c from public.coupons where shop_id = p_shop_id and code = v_code for update;
  else
    select * into c from public.coupons where shop_id = p_shop_id and code = v_code;
  end if;
  if not found then
    return jsonb_build_object('coupon_id', null, 'discount', 0, 'error', 'coupon_not_found');
  end if;

  select * into v_plan from private.current_plan(p_shop_id);
  if not c.active or not coalesce(v_plan.can_use_coupons, false) then
    return jsonb_build_object('coupon_id', null, 'discount', 0, 'error', 'coupon_inactive');
  end if;
  if c.expires_at is not null and c.expires_at <= now() then
    return jsonb_build_object('coupon_id', null, 'discount', 0, 'error', 'coupon_expired');
  end if;
  if c.usage_limit is not null and c.used_count >= c.usage_limit then
    return jsonb_build_object('coupon_id', null, 'discount', 0, 'error', 'coupon_exhausted');
  end if;
  if p_subtotal < c.minimum_order then
    return jsonb_build_object('coupon_id', null, 'discount', 0, 'error', 'coupon_min_order');
  end if;

  if c.discount_type = 'percentage' then
    v_disc := (p_subtotal * c.discount_value) / 100;
    if c.maximum_discount is not null then
      v_disc := least(v_disc, c.maximum_discount);
    end if;
  else
    v_disc := c.discount_value;
  end if;
  v_disc := least(v_disc, p_subtotal);

  return jsonb_build_object('coupon_id', c.id, 'discount', v_disc, 'error', null);
end
$$;

-- ---------- بررسی کوپن برای سبد خرید ----------
create or replace function public.validate_coupon(p_shop_id uuid, p_code text, p_subtotal bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  perform private.rate_limit('coupon_ip', private.client_ip(), 60, 600);
  perform private.rate_limit('coupon_shop', p_shop_id::text, 300, 600);
  if p_subtotal is null or p_subtotal < 0 then
    raise exception 'invalid_items';
  end if;
  if not exists (select 1 from public.shops where id = p_shop_id and status = 'active') then
    raise exception 'shop_not_found';
  end if;
  v := private.evaluate_coupon(p_shop_id, p_code, p_subtotal, false);
  return jsonb_build_object(
    'valid', ((v ->> 'error') is null),
    'discount', (v ->> 'discount')::bigint,
    'error', v ->> 'error'
  );
end
$$;

-- ---------- ثبت سفارش (قلب سیستم) ----------
-- p_items: [{"product_id":"...","variant_id":null,"quantity":2}, ...]
-- قیمت، موجودی، تخفیف و ارسال همه از دیتابیس حساب می‌شود، نه از مرورگر.
create or replace function public.place_order(
  p_shop_id uuid,
  p_items jsonb,
  p_customer_name text,
  p_customer_phone text,
  p_province text,
  p_city text,
  p_address text,
  p_postal_code text,
  p_note text,
  p_payment_method text,
  p_coupon_code text default null,
  p_session_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_shop public.shops;
  v_plan public.plans;
  v_settings public.shop_payment_settings;
  v_phone text := private.normalize_phone(p_customer_phone);
  v_postal text := private.normalize_postal(p_postal_code);
  v_name text := btrim(coalesce(p_customer_name, ''));
  v_province text := btrim(coalesce(p_province, ''));
  v_city text := btrim(coalesce(p_city, ''));
  v_address text := btrim(coalesce(p_address, ''));
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_line record;
  v_p public.products;
  v_v public.product_variants;
  v_unit bigint;
  v_avail int;
  v_label text;
  v_lines jsonb := '[]'::jsonb;
  v_subtotal bigint := 0;
  v_discount bigint := 0;
  v_shipping bigint := 0;
  v_total bigint;
  v_cp jsonb;
  v_coupon_id uuid;
  v_coupon_code text;
  v_customer_id uuid;
  v_order public.orders;
  v_provider text;
  v_payment_id uuid;
  v_count int;
begin
  -- ۱) اعتبارسنجی ورودی
  if char_length(v_name) < 2 or char_length(v_name) > 80 then
    raise exception 'invalid_name';
  end if;
  if v_phone !~ '^09[0-9]{9}$' then
    raise exception 'invalid_phone';
  end if;
  if char_length(v_province) not between 2 and 40
     or char_length(v_city) not between 2 and 40
     or char_length(v_address) not between 10 and 500 then
    raise exception 'invalid_address';
  end if;
  if v_postal !~ '^[0-9]{10}$' then
    raise exception 'invalid_postal_code';
  end if;
  if v_note is not null and char_length(v_note) > 500 then
    raise exception 'invalid_note';
  end if;
  if coalesce(p_payment_method, '') not in ('card_to_card', 'online') then
    raise exception 'invalid_payment_method';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'invalid_items';
  end if;
  if jsonb_array_length(p_items) not between 1 and 30 then
    raise exception 'invalid_items';
  end if;
  begin
    perform (e ->> 'product_id')::uuid,
            nullif(e ->> 'variant_id', '')::uuid,
            (e ->> 'quantity')::int
       from jsonb_array_elements(p_items) e;
  exception when others then
    raise exception 'invalid_items';
  end;
  if exists (
    select 1 from jsonb_array_elements(p_items) e
     where jsonb_typeof(e) <> 'object'
        or (e ->> 'product_id') is null
        or coalesce((e ->> 'quantity')::int, 0) not between 1 and 99
  ) then
    raise exception 'invalid_items';
  end if;

  -- ۲) محدودیت نرخ
  perform private.rate_limit('order_phone', v_phone, 5, 3600);
  perform private.rate_limit('order_ip', private.client_ip(), 20, 3600);
  perform private.rate_limit('order_shop', p_shop_id::text, 200, 3600);

  -- ۳) فروشگاه، سقف سفارش پلن، روش پرداخت
  select * into v_shop from public.shops where id = p_shop_id and status = 'active';
  if not found then
    raise exception 'shop_not_found';
  end if;

  select * into v_plan from private.current_plan(v_shop.id);
  if v_plan.max_orders_per_30d is not null then
    select count(*) into v_count from public.orders
     where shop_id = v_shop.id and created_at > now() - interval '30 days';
    if v_count >= v_plan.max_orders_per_30d then
      raise exception 'shop_order_limit_reached';
    end if;
  end if;

  select * into v_settings from public.shop_payment_settings where shop_id = v_shop.id;
  if p_payment_method = 'card_to_card' then
    if not coalesce(v_settings.card_enabled, false) or v_settings.card_number is null then
      raise exception 'payment_method_unavailable';
    end if;
    v_provider := 'card_to_card';
  else
    v_provider := coalesce(v_settings.online_provider, 'none');
    if v_provider = 'none' then
      raise exception 'payment_method_unavailable';
    end if;
    if v_provider = 'mock' and not coalesce(
         (select (s.value)::text = 'true' from public.app_settings s where s.key = 'allow_mock_payments'),
         false) then
      raise exception 'payment_method_unavailable';
    end if;
  end if;

  -- ۴) آیتم‌ها: قفل ردیف‌ها به ترتیب ثابت (جلوگیری از deadlock) و محاسبهٔ قیمت
  for v_line in
    select (e ->> 'product_id')::uuid as product_id,
           nullif(e ->> 'variant_id', '')::uuid as variant_id,
           sum((e ->> 'quantity')::int)::int as qty
      from jsonb_array_elements(p_items) e
     group by 1, 2
     order by 1, 2
  loop
    if v_line.qty > 99 then
      raise exception 'invalid_items';
    end if;

    select * into v_p from public.products
     where id = v_line.product_id and shop_id = v_shop.id and status = 'active'
     for update;
    if not found then
      raise exception 'product_unavailable';
    end if;

    v_v := null;
    v_label := null;
    if v_p.has_variants then
      if v_line.variant_id is null then
        raise exception 'variant_required';
      end if;
      select * into v_v from public.product_variants
       where id = v_line.variant_id and product_id = v_p.id and is_active
       for update;
      if not found then
        raise exception 'product_unavailable';
      end if;
      v_unit := coalesce(v_v.price_override, v_p.discount_price, v_p.price);
      v_avail := v_v.stock;
      select string_agg(a.value, ' / ' order by a.key) into v_label
        from jsonb_each_text(v_v.attributes) a;
    else
      if v_line.variant_id is not null then
        raise exception 'product_unavailable';
      end if;
      v_unit := coalesce(v_p.discount_price, v_p.price);
      v_avail := v_p.stock;
    end if;

    if v_avail < v_line.qty then
      raise exception 'insufficient_stock';
    end if;

    v_subtotal := v_subtotal + (v_unit * v_line.qty);
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'product_id', v_p.id,
      'variant_id', case when v_p.has_variants then v_v.id else null end,
      'title', v_p.title,
      'variant_label', v_label,
      'unit_price', v_unit,
      'qty', v_line.qty
    ));
  end loop;

  -- ۵) کوپن و ارسال
  v_cp := private.evaluate_coupon(v_shop.id, p_coupon_code, v_subtotal, true);
  if (v_cp ->> 'error') is not null then
    raise exception '%', v_cp ->> 'error';
  end if;
  v_discount := coalesce((v_cp ->> 'discount')::bigint, 0);
  v_coupon_id := nullif(v_cp ->> 'coupon_id', '')::uuid;
  v_coupon_code := case when v_coupon_id is not null then upper(btrim(p_coupon_code)) else null end;

  if v_shop.free_shipping_over is not null and (v_subtotal - v_discount) >= v_shop.free_shipping_over then
    v_shipping := 0;
  else
    v_shipping := v_shop.shipping_fee;
  end if;
  v_total := v_subtotal - v_discount + v_shipping;

  -- ۶) مشتری و آدرس
  insert into public.customers (shop_id, name, phone, orders_count, total_spent, last_order_at)
  values (v_shop.id, v_name, v_phone, 1, v_total, now())
  on conflict (shop_id, phone) do update
    set name = excluded.name,
        orders_count = public.customers.orders_count + 1,
        total_spent = public.customers.total_spent + excluded.total_spent,
        last_order_at = now()
  returning id into v_customer_id;

  if not exists (
    select 1 from public.addresses a
     where a.customer_id = v_customer_id and a.postal_code = v_postal and a.address = v_address
  ) then
    insert into public.addresses (customer_id, shop_id, province, city, address, postal_code)
    values (v_customer_id, v_shop.id, v_province, v_city, v_address, v_postal);
  end if;

  -- ۷) سفارش و آیتم‌ها
  insert into public.orders (
    shop_id, customer_id, customer_name, customer_phone, province, city, address, postal_code,
    note, subtotal, discount, shipping, total, coupon_id, coupon_code, payment_method
  ) values (
    v_shop.id, v_customer_id, v_name, v_phone, v_province, v_city, v_address, v_postal,
    v_note, v_subtotal, v_discount, v_shipping, v_total, v_coupon_id, v_coupon_code, p_payment_method
  )
  returning * into v_order;

  insert into public.order_items (
    order_id, shop_id, product_id, variant_id, title_snapshot, variant_snapshot,
    unit_price, quantity, line_total
  )
  select v_order.id, v_shop.id, x.product_id, x.variant_id, x.title, x.variant_label,
         x.unit_price, x.qty, x.unit_price * x.qty
    from jsonb_to_recordset(v_lines)
      as x(product_id uuid, variant_id uuid, title text, variant_label text, unit_price bigint, qty int);

  -- کم کردن موجودی: اول Variantها، بعد محصول (تریگر موجودی محصول را از Variantها حساب می‌کند)
  update public.product_variants v
     set stock = v.stock - x.qty
    from jsonb_to_recordset(v_lines)
      as x(product_id uuid, variant_id uuid, title text, variant_label text, unit_price bigint, qty int)
   where v.id = x.variant_id;

  update public.products p
     set sales_count = p.sales_count + a.q,
         stock = case when p.has_variants then p.stock else p.stock - a.q end
    from (select y.product_id, sum(y.qty)::int as q
            from jsonb_to_recordset(v_lines) as y(product_id uuid, qty int)
           group by y.product_id) a
   where p.id = a.product_id;

  -- ۸) استفادهٔ کوپن
  if v_coupon_id is not null then
    insert into public.coupon_usages (coupon_id, order_id, shop_id, customer_phone, discount_amount)
    values (v_coupon_id, v_order.id, v_shop.id, v_phone, v_discount);
    update public.coupons set used_count = used_count + 1 where id = v_coupon_id;
  end if;

  -- ۹) پرداخت (جمع صفر = پرداخت‌شده)
  insert into public.payments (order_id, shop_id, provider, amount, status, paid_at)
  values (
    v_order.id, v_shop.id, v_provider, v_total,
    case when v_total = 0 then 'paid' else 'pending' end,
    case when v_total = 0 then now() else null end
  )
  returning id into v_payment_id;

  -- ۱۰) رویداد خرید (فقط سمت سرور ثبت می‌شود)
  if p_session_id is not null and p_session_id ~ '^[A-Za-z0-9_-]{8,64}$' then
    insert into public.analytics_events (shop_id, event_type, session_id)
    values (v_shop.id, 'purchase', p_session_id);
  end if;

  return jsonb_build_object(
    'order_id', v_order.id,
    'order_number', v_order.order_number,
    'total', v_order.total,
    'payment_id', v_payment_id,
    'payment_method', p_payment_method,
    'provider', v_provider,
    'payment_status', (select o.payment_status from public.orders o where o.id = v_order.id),
    'card', case
      when v_provider = 'card_to_card'
      then jsonb_build_object('number', v_settings.card_number, 'holder', v_settings.card_holder)
      else null
    end
  );
end
$$;

-- ---------- پیگیری سفارش (مهمان): شماره سفارش + ۴ رقم آخر موبایل ----------
-- برای جلوگیری از حدس‌زدن، پیدا نشدن خطا نمی‌دهد و found=false برمی‌گرداند
-- (تا شمارندهٔ محدودیت نرخ ثبت شود).
create or replace function public.track_order(p_order_number text, p_phone_last4 text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_num text := upper(btrim(coalesce(p_order_number, '')));
  v_last4 text := private.normalize_digits(btrim(coalesce(p_phone_last4, '')));
  v_o public.orders;
  v_shop public.shops;
  v_pay public.payments;
  v_settings public.shop_payment_settings;
  v_items jsonb;
begin
  if v_num !~ '^SH-[0-9]{4,12}$' or v_last4 !~ '^[0-9]{4}$' then
    return jsonb_build_object('found', false);
  end if;
  perform private.rate_limit('track_ip', private.client_ip(), 60, 600);
  perform private.rate_limit('track_order', v_num, 8, 600);

  select * into v_o from public.orders
   where order_number = v_num and right(customer_phone, 4) = v_last4;
  if not found then
    return jsonb_build_object('found', false);
  end if;

  select * into v_shop from public.shops where id = v_o.shop_id;
  select * into v_pay from public.payments where order_id = v_o.id order by created_at desc limit 1;
  select * into v_settings from public.shop_payment_settings where shop_id = v_o.shop_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'title', i.title_snapshot,
           'variant', i.variant_snapshot,
           'unit_price', i.unit_price,
           'quantity', i.quantity,
           'line_total', i.line_total
         ) order by i.created_at, i.id), '[]'::jsonb)
    into v_items
    from public.order_items i
   where i.order_id = v_o.id;

  return jsonb_build_object(
    'found', true,
    'order_number', v_o.order_number,
    'order_status', v_o.order_status,
    'payment_status', v_o.payment_status,
    'payment_method', v_o.payment_method,
    'subtotal', v_o.subtotal,
    'discount', v_o.discount,
    'shipping', v_o.shipping,
    'total', v_o.total,
    'customer_name', v_o.customer_name,
    'province', v_o.province,
    'city', v_o.city,
    'address', v_o.address,
    'postal_code', v_o.postal_code,
    'note', v_o.note,
    'shipping_tracking_code', v_o.shipping_tracking_code,
    'created_at', v_o.created_at,
    'receipt_submitted', (v_pay.receipt_submitted_at is not null),
    'items', v_items,
    'shop', jsonb_build_object(
      'name', v_shop.name,
      'username', v_shop.username,
      'phone', v_shop.phone,
      'whatsapp', v_shop.whatsapp,
      'telegram', v_shop.telegram,
      'instagram', v_shop.instagram
    ),
    'card', case
      when v_pay.provider = 'card_to_card' and v_pay.status = 'pending'
      then jsonb_build_object('number', v_settings.card_number, 'holder', v_settings.card_holder)
      else null
    end
  );
end
$$;

-- ---------- ثبت شمارهٔ پیگیری واریز کارت‌به‌کارت توسط مشتری ----------
create or replace function public.submit_payment_receipt(p_order_number text, p_phone_last4 text, p_reference text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_num text := upper(btrim(coalesce(p_order_number, '')));
  v_last4 text := private.normalize_digits(btrim(coalesce(p_phone_last4, '')));
  v_ref text := btrim(coalesce(p_reference, ''));
  v_o public.orders;
begin
  if char_length(v_ref) < 3 or char_length(v_ref) > 100 then
    raise exception 'invalid_receipt';
  end if;
  if v_num !~ '^SH-[0-9]{4,12}$' or v_last4 !~ '^[0-9]{4}$' then
    return jsonb_build_object('ok', false, 'error', 'order_not_found');
  end if;
  perform private.rate_limit('track_ip', private.client_ip(), 60, 600);
  perform private.rate_limit('track_order', v_num, 8, 600);

  select * into v_o from public.orders
   where order_number = v_num and right(customer_phone, 4) = v_last4;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'order_not_found');
  end if;

  update public.payments
     set receipt_reference = v_ref, receipt_submitted_at = now()
   where order_id = v_o.id and provider = 'card_to_card' and status = 'pending';
  if not found then
    return jsonb_build_object('ok', false, 'error', 'payment_not_pending');
  end if;
  return jsonb_build_object('ok', true);
end
$$;

-- ---------- ثبت رویداد آمار (بازدید، افزودن به سبد، شروع پرداخت) ----------
-- رویداد نامعتبر بی‌صدا نادیده گرفته می‌شود تا تجربهٔ کاربر خراب نشود.
create or replace function public.track_event(p_shop_id uuid, p_event_type text, p_session_id text, p_product_id uuid default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(p_event_type, '') not in ('shop_view', 'product_view', 'add_to_cart', 'checkout_start') then
    return;
  end if;
  if p_session_id is null or p_session_id !~ '^[A-Za-z0-9_-]{8,64}$' then
    return;
  end if;
  perform private.rate_limit('event_session', p_session_id, 120, 600);
  if not exists (select 1 from public.shops where id = p_shop_id and status = 'active') then
    return;
  end if;
  if p_product_id is not null
     and not exists (select 1 from public.products where id = p_product_id and shop_id = p_shop_id) then
    p_product_id := null;
  end if;
  insert into public.analytics_events (shop_id, event_type, product_id, session_id)
  values (p_shop_id, p_event_type, p_product_id, p_session_id);
end
$$;

-- ---------- بررسی آزاد بودن username (Onboarding) ----------
create or replace function public.check_username_available(p_username text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v text := lower(btrim(coalesce(p_username, '')));
begin
  perform private.rate_limit('username_ip', private.client_ip(), 120, 600);
  if v !~ '^[a-z0-9_]{3,30}$' or private.is_reserved_username(v) then
    return false;
  end if;
  return not exists (select 1 from public.shops where username = v);
end
$$;

-- ---------- گزارش تخلف فروشگاه یا محصول ----------
create or replace function public.report_content(p_target_type text, p_target_id uuid, p_reason text, p_contact text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reason text := btrim(coalesce(p_reason, ''));
  v_contact text := nullif(btrim(coalesce(p_contact, '')), '');
begin
  if coalesce(p_target_type, '') not in ('shop', 'product') or p_target_id is null then
    raise exception 'invalid_report';
  end if;
  if char_length(v_reason) not between 3 and 1000 then
    raise exception 'invalid_report';
  end if;
  if v_contact is not null and char_length(v_contact) > 100 then
    raise exception 'invalid_report';
  end if;
  perform private.rate_limit('report_ip', private.client_ip(), 10, 3600);
  perform private.rate_limit('report_target', p_target_id::text, 30, 86400);
  if p_target_type = 'shop' and not exists (select 1 from public.shops where id = p_target_id) then
    raise exception 'invalid_report';
  end if;
  if p_target_type = 'product' and not exists (select 1 from public.products where id = p_target_id) then
    raise exception 'invalid_report';
  end if;
  insert into public.reports (reporter_id, target_type, target_id, reason, contact)
  values ((select auth.uid()), p_target_type, p_target_id, v_reason, v_contact);
end
$$;

-- ---------- توابع فروشنده ----------
-- تأیید دریافت واریز کارت‌به‌کارت
create or replace function public.confirm_payment(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o public.orders;
  v_pay public.payments;
begin
  select * into v_o from public.orders where id = p_order_id;
  if not found
     or not (v_o.shop_id in (select private.writable_shop_ids()) or private.is_admin()) then
    raise exception 'order_not_found';
  end if;
  if v_o.order_status = 'cancelled' then
    raise exception 'order_cancelled';
  end if;
  select * into v_pay from public.payments
   where order_id = v_o.id and provider = 'card_to_card' and status = 'pending'
   for update;
  if not found then
    raise exception 'payment_not_pending';
  end if;
  update public.payments set status = 'paid', paid_at = now() where id = v_pay.id;
  return jsonb_build_object('ok', true);
end
$$;

-- ثبت بازپرداخت برای سفارش لغوشدهٔ پرداخت‌شده (خود بازپرداخت دستی انجام می‌شود)
create or replace function public.mark_refunded(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o public.orders;
begin
  select * into v_o from public.orders where id = p_order_id;
  if not found
     or not (v_o.shop_id in (select private.writable_shop_ids()) or private.is_admin()) then
    raise exception 'order_not_found';
  end if;
  if v_o.order_status <> 'cancelled' then
    raise exception 'order_not_cancelled';
  end if;
  update public.payments set status = 'refunded' where order_id = v_o.id and status = 'paid';
  if not found then
    raise exception 'payment_not_paid';
  end if;
  return jsonb_build_object('ok', true);
end
$$;

-- داشبورد فروشنده در یک فراخوانی (بدون N+1)
-- «فروش» = سفارش‌های پرداخت‌شده و لغو‌نشده. «امروز» و «این ماه» به وقت تهران و ماه شمسی.
create or replace function public.seller_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_shop_id uuid;
  v_today date := (now() at time zone 'Asia/Tehran')::date;
  v_today_start timestamptz;
  v_month_start timestamptz;
  v_result jsonb;
begin
  select s.id into v_shop_id from public.shops s where s.owner_id = (select auth.uid());
  if v_shop_id is null then
    raise exception 'shop_not_found';
  end if;

  v_today_start := v_today::timestamp at time zone 'Asia/Tehran';
  v_month_start := (v_today - (private.jalali_day_of_month(v_today) - 1))::timestamp at time zone 'Asia/Tehran';

  select jsonb_build_object(
    'shop_id', v_shop_id,
    'sales_today', coalesce(sum(o.total) filter (
      where o.payment_status = 'paid' and o.order_status <> 'cancelled' and o.created_at >= v_today_start), 0),
    'sales_month', coalesce(sum(o.total) filter (
      where o.payment_status = 'paid' and o.order_status <> 'cancelled' and o.created_at >= v_month_start), 0),
    'orders_today', count(*) filter (where o.created_at >= v_today_start),
    'orders_month', count(*) filter (where o.created_at >= v_month_start),
    'orders_total', count(*),
    'orders_new', count(*) filter (where o.order_status = 'new'),
    'orders_awaiting_payment', count(*) filter (where o.payment_status = 'pending' and o.order_status <> 'cancelled')
  )
  into v_result
  from public.orders o
  where o.shop_id = v_shop_id;

  v_result := v_result || (
    select jsonb_build_object(
      'products_count', count(*) filter (where p.status <> 'archived'),
      'low_stock_count', count(*) filter (where p.status = 'active' and p.stock between 1 and 3),
      'out_of_stock_count', count(*) filter (where p.status = 'active' and p.stock = 0)
    )
    from public.products p
    where p.shop_id = v_shop_id
  );

  v_result := v_result || jsonb_build_object('low_stock_items', (
    select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'title', t.title, 'stock', t.stock)
                              order by t.stock, t.title), '[]'::jsonb)
    from (select p.id, p.title, p.stock
            from public.products p
           where p.shop_id = v_shop_id and p.status = 'active' and p.stock <= 3
           order by p.stock, p.title
           limit 5) t
  ));

  v_result := v_result || jsonb_build_object('daily', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'date', d.dt::date, 'sales', coalesce(x.sales, 0), 'orders', coalesce(x.orders, 0)
           ) order by d.dt), '[]'::jsonb)
    from generate_series((v_today - 13)::timestamp, v_today::timestamp, interval '1 day') as d(dt)
    left join (
      select (o.created_at at time zone 'Asia/Tehran')::date as dy,
             sum(o.total) filter (where o.payment_status = 'paid' and o.order_status <> 'cancelled') as sales,
             count(*) as orders
        from public.orders o
       where o.shop_id = v_shop_id
         and o.created_at >= ((v_today - 13)::timestamp at time zone 'Asia/Tehran')
       group by 1
    ) x on x.dy = d.dt::date
  ));

  return v_result;
end
$$;
