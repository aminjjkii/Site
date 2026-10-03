-- =====================================================================
-- ShopYar | 0001_schema.sql
-- جدول‌ها، قیدها، ایندکس‌ها و داده‌های پایه (پلن‌ها و تنظیمات)
-- نیازمند Postgres 15 یا بالاتر. اول از همه اجرا می‌شود.
-- قراردادها: کلید اصلی uuid | پول bigint (واحد پیش‌فرض: تومان)
-- وضعیت‌ها text + CHECK | ستون shop_id در جدول‌های فرزند (برای RLS سریع)
-- کلید خارجی ترکیبی (id, shop_id) تضمین می‌کند ردیف‌های یک فروشگاه
-- هرگز به ردیف‌های فروشگاه دیگر وصل نشوند.
-- =====================================================================

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated, service_role;

-- نام‌های رزروشده برای username فروشگاه (با مسیرهای سایت تداخل نکنند)
create or replace function private.is_reserved_username(p text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p = any (array[
    'admin','administrator','api','app','assets','auth','blog','cart','checkout','dashboard',
    'help','login','logout','mail','null','onboarding','order','orders','pricing','privacy',
    'product','products','public','register','root','settings','shop','shops','shopyar','signup',
    'static','support','terms','track','undefined','www'
  ])
$$;

-- ---------------------------------------------------------------------
-- plans: پیکربندی پلن‌ها (قابل‌تغییر با UPDATE)
-- ---------------------------------------------------------------------
create table public.plans (
  code text primary key,
  name text not null,
  price bigint not null default 0,
  max_products int,
  max_orders_per_30d int,
  can_use_coupons boolean not null default false,
  analytics_level text not null default 'none',
  features jsonb not null default '[]'::jsonb,
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint plans_code_fmt check (code ~ '^[a-z0-9_]{2,20}$'),
  constraint plans_price_chk check (price >= 0),
  constraint plans_max_products_chk check (max_products is null or max_products > 0),
  constraint plans_max_orders_chk check (max_orders_per_30d is null or max_orders_per_30d > 0),
  constraint plans_analytics_chk check (analytics_level in ('none','basic','advanced'))
);
comment on column public.plans.max_orders_per_30d is 'سقف سفارش در ۳۰ روز اخیر (پنجرهٔ لغزان). null = نامحدود';

-- ---------------------------------------------------------------------
-- profiles: یک ردیف به ازای هر کاربر Auth (با Trigger ساخته می‌شود)
-- ---------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  phone text,
  role text not null default 'seller',
  is_blocked boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_full_name_len check (full_name is null or char_length(full_name) between 1 and 80),
  constraint profiles_phone_fmt check (phone is null or phone ~ '^09[0-9]{9}$'),
  constraint profiles_role_chk check (role in ('seller','admin'))
);

-- ---------------------------------------------------------------------
-- shops: در MVP هر فروشنده یک فروشگاه (unique owner_id)
-- ---------------------------------------------------------------------
create table public.shops (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  username text not null,
  name text not null,
  description text,
  category text,
  logo_path text,
  currency text not null default 'IRT',
  shipping_fee bigint not null default 0,
  free_shipping_over bigint,
  status text not null default 'active',
  instagram text,
  whatsapp text,
  telegram text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shops_owner_uq unique (owner_id),
  constraint shops_username_uq unique (username),
  constraint shops_username_fmt check (username ~ '^[a-z0-9_]{3,30}$'),
  constraint shops_username_reserved check (not private.is_reserved_username(username)),
  constraint shops_name_len check (char_length(name) between 2 and 60),
  constraint shops_description_len check (description is null or char_length(description) <= 500),
  constraint shops_category_len check (category is null or char_length(category) <= 40),
  constraint shops_logo_len check (logo_path is null or char_length(logo_path) <= 300),
  constraint shops_currency_chk check (currency in ('IRT','IRR')),
  constraint shops_shipping_fee_chk check (shipping_fee >= 0),
  constraint shops_free_shipping_chk check (free_shipping_over is null or free_shipping_over > 0),
  constraint shops_status_chk check (status in ('active','suspended')),
  constraint shops_instagram_fmt check (instagram is null or instagram ~ '^[A-Za-z0-9._]{1,30}$'),
  constraint shops_whatsapp_fmt check (whatsapp is null or whatsapp ~ '^\+?[0-9]{8,15}$'),
  constraint shops_telegram_fmt check (telegram is null or telegram ~ '^[A-Za-z0-9_]{5,32}$'),
  constraint shops_phone_fmt check (phone is null or phone ~ '^\+?[0-9]{8,15}$')
);

-- ---------------------------------------------------------------------
-- shop_payment_settings: فقط مالک می‌خواند. شمارهٔ کارت فقط از RPC سفارش
-- کارت‌به‌کارت به مشتری نشان داده می‌شود. کلید سرّی درگاه اینجا ذخیره نمی‌شود.
-- ---------------------------------------------------------------------
create table public.shop_payment_settings (
  shop_id uuid primary key references public.shops (id) on delete cascade,
  card_enabled boolean not null default false,
  card_number text,
  card_holder text,
  online_provider text not null default 'none',
  zarinpal_merchant_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sps_card_number_fmt check (card_number is null or card_number ~ '^[0-9]{16}$'),
  constraint sps_card_holder_len check (card_holder is null or char_length(card_holder) <= 80),
  constraint sps_card_requires_number check (not card_enabled or card_number is not null),
  constraint sps_provider_chk check (online_provider in ('none','mock','zarinpal')),
  constraint sps_merchant_fmt check (zarinpal_merchant_id is null or zarinpal_merchant_id ~ '^[A-Za-z0-9-]{10,64}$')
);

-- ---------------------------------------------------------------------
-- categories
-- ---------------------------------------------------------------------
create table public.categories (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id) on delete cascade,
  name text not null,
  slug text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  constraint categories_name_len check (char_length(name) between 1 and 40),
  constraint categories_slug_len check (char_length(slug) between 1 and 60),
  constraint categories_shop_slug_uq unique (shop_id, slug),
  constraint categories_id_shop_uq unique (id, shop_id)
);

-- ---------------------------------------------------------------------
-- products
-- ---------------------------------------------------------------------
create table public.products (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id) on delete cascade,
  category_id uuid,
  title text not null,
  description text,
  price bigint not null,
  discount_price bigint,
  stock int not null default 0,
  sku text,
  status text not null default 'active',
  featured boolean not null default false,
  has_variants boolean not null default false,
  sales_count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint products_id_shop_uq unique (id, shop_id),
  constraint products_category_fk foreign key (category_id, shop_id)
    references public.categories (id, shop_id) on delete set null (category_id),
  constraint products_title_len check (char_length(title) between 2 and 120),
  constraint products_description_len check (description is null or char_length(description) <= 5000),
  constraint products_price_chk check (price > 0),
  constraint products_discount_chk check (discount_price is null or (discount_price > 0 and discount_price < price)),
  constraint products_stock_chk check (stock >= 0),
  constraint products_sku_len check (sku is null or char_length(sku) between 1 and 64),
  constraint products_status_chk check (status in ('draft','active','archived')),
  constraint products_sales_chk check (sales_count >= 0)
);
create unique index products_shop_sku_uq on public.products (shop_id, sku) where sku is not null;
create index products_shop_status_created_idx on public.products (shop_id, status, created_at desc);
create index products_shop_featured_idx on public.products (shop_id) where featured and status = 'active';
create index products_shop_sales_idx on public.products (shop_id, sales_count desc) where status = 'active';
create index products_category_idx on public.products (category_id) where category_id is not null;

-- ---------------------------------------------------------------------
-- product_images: path = مسیر فایل در bucket به نام product-images
-- ---------------------------------------------------------------------
create table public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null,
  shop_id uuid not null,
  path text not null,
  alt text,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  constraint product_images_product_fk foreign key (product_id, shop_id)
    references public.products (id, shop_id) on delete cascade,
  constraint product_images_path_uq unique (path),
  constraint product_images_order_uq unique (product_id, sort_order) deferrable initially deferred,
  constraint product_images_path_len check (char_length(path) between 1 and 300),
  constraint product_images_alt_len check (alt is null or char_length(alt) <= 200),
  constraint product_images_order_chk check (sort_order >= 0)
);
create index product_images_shop_idx on public.product_images (shop_id);

-- ---------------------------------------------------------------------
-- product_variants: attributes مثل {"رنگ":"مشکی","سایز":"M"}
-- price_override اگر پر باشد، قیمت نهایی همین Variant است (جایگزین قیمت و تخفیف محصول)
-- ---------------------------------------------------------------------
create table public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null,
  shop_id uuid not null,
  attributes jsonb not null,
  sku text,
  stock int not null default 0,
  price_override bigint,
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint product_variants_product_fk foreign key (product_id, shop_id)
    references public.products (id, shop_id) on delete cascade,
  constraint product_variants_id_shop_uq unique (id, shop_id),
  constraint product_variants_attrs_uq unique (product_id, attributes),
  constraint product_variants_attrs_chk check (jsonb_typeof(attributes) = 'object' and attributes <> '{}'::jsonb),
  constraint product_variants_sku_len check (sku is null or char_length(sku) between 1 and 64),
  constraint product_variants_stock_chk check (stock >= 0),
  constraint product_variants_price_chk check (price_override is null or price_override > 0)
);
create unique index product_variants_shop_sku_uq on public.product_variants (shop_id, sku) where sku is not null;
create index product_variants_shop_idx on public.product_variants (shop_id);

-- ---------------------------------------------------------------------
-- customers: مشتری‌های هر فروشگاه (مهمان، بدون حساب کاربری)
-- ---------------------------------------------------------------------
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id) on delete cascade,
  name text not null,
  phone text not null,
  orders_count int not null default 0,
  total_spent bigint not null default 0,
  last_order_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint customers_shop_phone_uq unique (shop_id, phone),
  constraint customers_id_shop_uq unique (id, shop_id),
  constraint customers_name_len check (char_length(name) between 2 and 80),
  constraint customers_phone_fmt check (phone ~ '^09[0-9]{9}$'),
  constraint customers_counts_chk check (orders_count >= 0 and total_spent >= 0)
);

create table public.addresses (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null,
  shop_id uuid not null,
  province text not null,
  city text not null,
  address text not null,
  postal_code text not null,
  created_at timestamptz not null default now(),
  constraint addresses_customer_fk foreign key (customer_id, shop_id)
    references public.customers (id, shop_id) on delete cascade,
  constraint addresses_postal_fmt check (postal_code ~ '^[0-9]{10}$'),
  constraint addresses_len check (
    char_length(province) between 2 and 40 and char_length(city) between 2 and 40
    and char_length(address) between 10 and 500
  )
);
create index addresses_customer_idx on public.addresses (customer_id);
create index addresses_shop_idx on public.addresses (shop_id);

-- ---------------------------------------------------------------------
-- coupons: کد همیشه با حروف بزرگ ذخیره می‌شود
-- ---------------------------------------------------------------------
create table public.coupons (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id) on delete cascade,
  code text not null,
  discount_type text not null,
  discount_value bigint not null,
  minimum_order bigint not null default 0,
  maximum_discount bigint,
  expires_at timestamptz,
  usage_limit int,
  used_count int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint coupons_id_shop_uq unique (id, shop_id),
  constraint coupons_code_fmt check (code ~ '^[A-Z0-9_-]{3,24}$'),
  constraint coupons_type_chk check (discount_type in ('percentage','fixed')),
  constraint coupons_value_chk check (discount_value > 0),
  constraint coupons_percent_chk check (discount_type <> 'percentage' or discount_value <= 100),
  constraint coupons_min_chk check (minimum_order >= 0),
  constraint coupons_max_chk check (maximum_discount is null or maximum_discount > 0),
  constraint coupons_limit_chk check (usage_limit is null or usage_limit > 0),
  constraint coupons_used_chk check (used_count >= 0)
);
create unique index coupons_shop_code_uq on public.coupons (shop_id, code);

-- ---------------------------------------------------------------------
-- orders
-- شماره سفارش: SH-10001 و بالاتر (sequence سراسری)
-- ---------------------------------------------------------------------
create sequence public.order_number_seq as bigint start with 10001 minvalue 10001;

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null default ('SH-' || nextval('public.order_number_seq')::text),
  shop_id uuid not null references public.shops (id) on delete cascade,
  customer_id uuid,
  customer_name text not null,
  customer_phone text not null,
  province text not null,
  city text not null,
  address text not null,
  postal_code text not null,
  note text,
  internal_note text,
  subtotal bigint not null,
  discount bigint not null default 0,
  shipping bigint not null default 0,
  total bigint not null,
  coupon_id uuid,
  coupon_code text,
  payment_method text not null,
  payment_status text not null default 'pending',
  order_status text not null default 'new',
  shipping_tracking_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint orders_number_uq unique (order_number),
  constraint orders_id_shop_uq unique (id, shop_id),
  constraint orders_customer_fk foreign key (customer_id, shop_id)
    references public.customers (id, shop_id) on delete set null (customer_id),
  constraint orders_coupon_fk foreign key (coupon_id, shop_id)
    references public.coupons (id, shop_id) on delete set null (coupon_id),
  constraint orders_phone_fmt check (customer_phone ~ '^09[0-9]{9}$'),
  constraint orders_postal_fmt check (postal_code ~ '^[0-9]{10}$'),
  constraint orders_note_len check (note is null or char_length(note) <= 500),
  constraint orders_internal_note_len check (internal_note is null or char_length(internal_note) <= 1000),
  constraint orders_tracking_len check (shipping_tracking_code is null or char_length(shipping_tracking_code) <= 64),
  constraint orders_amounts_chk check (subtotal >= 0 and discount >= 0 and shipping >= 0 and discount <= subtotal),
  constraint orders_total_chk check (total = subtotal - discount + shipping),
  constraint orders_payment_method_chk check (payment_method in ('card_to_card','online')),
  constraint orders_payment_status_chk check (payment_status in ('pending','paid','failed','cancelled','refunded')),
  constraint orders_status_chk check (order_status in ('new','confirmed','processing','shipped','delivered','cancelled'))
);
create index orders_shop_created_idx on public.orders (shop_id, created_at desc);
create index orders_shop_status_idx on public.orders (shop_id, order_status, created_at desc);
create index orders_shop_phone_idx on public.orders (shop_id, customer_phone);
create index orders_customer_idx on public.orders (customer_id) where customer_id is not null;
create index orders_coupon_idx on public.orders (coupon_id) where coupon_id is not null;

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null,
  shop_id uuid not null,
  product_id uuid,
  variant_id uuid,
  title_snapshot text not null,
  variant_snapshot text,
  unit_price bigint not null,
  quantity int not null,
  line_total bigint not null,
  created_at timestamptz not null default now(),
  constraint order_items_order_fk foreign key (order_id, shop_id)
    references public.orders (id, shop_id) on delete cascade,
  constraint order_items_product_fk foreign key (product_id, shop_id)
    references public.products (id, shop_id) on delete set null (product_id),
  constraint order_items_variant_fk foreign key (variant_id, shop_id)
    references public.product_variants (id, shop_id) on delete set null (variant_id),
  constraint order_items_price_chk check (unit_price > 0),
  constraint order_items_qty_chk check (quantity between 1 and 99),
  constraint order_items_total_chk check (line_total = unit_price * quantity)
);
create index order_items_order_idx on public.order_items (order_id);
create index order_items_shop_idx on public.order_items (shop_id);
create index order_items_product_idx on public.order_items (product_id) where product_id is not null;
create index order_items_variant_idx on public.order_items (variant_id) where variant_id is not null;

create table public.coupon_usages (
  id uuid primary key default gen_random_uuid(),
  coupon_id uuid not null,
  order_id uuid not null,
  shop_id uuid not null,
  customer_phone text not null,
  discount_amount bigint not null,
  created_at timestamptz not null default now(),
  constraint coupon_usages_coupon_fk foreign key (coupon_id, shop_id)
    references public.coupons (id, shop_id) on delete cascade,
  constraint coupon_usages_order_fk foreign key (order_id, shop_id)
    references public.orders (id, shop_id) on delete cascade,
  constraint coupon_usages_order_uq unique (order_id),
  constraint coupon_usages_amount_chk check (discount_amount >= 0)
);
create index coupon_usages_coupon_idx on public.coupon_usages (coupon_id);
create index coupon_usages_shop_idx on public.coupon_usages (shop_id);

-- ---------------------------------------------------------------------
-- payments: فقط توابع سمت سرور می‌نویسند
-- ---------------------------------------------------------------------
create table public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null,
  shop_id uuid not null,
  provider text not null,
  amount bigint not null,
  status text not null default 'pending',
  provider_ref text,
  receipt_reference text,
  receipt_submitted_at timestamptz,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payments_order_fk foreign key (order_id, shop_id)
    references public.orders (id, shop_id) on delete cascade,
  constraint payments_provider_chk check (provider in ('mock','card_to_card','zarinpal')),
  constraint payments_amount_chk check (amount >= 0),
  constraint payments_status_chk check (status in ('pending','paid','failed','cancelled','refunded')),
  constraint payments_receipt_len check (receipt_reference is null or char_length(receipt_reference) <= 100)
);
create unique index payments_order_active_uq on public.payments (order_id) where status in ('pending','paid');
create index payments_order_idx on public.payments (order_id);
create index payments_shop_idx on public.payments (shop_id, created_at desc);

-- ---------------------------------------------------------------------
-- subscriptions: ساختار واقعی؛ پرداخت اشتراک فعلاً Mock است (فاز ۱۴)
-- ---------------------------------------------------------------------
create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id) on delete cascade,
  plan_code text not null references public.plans (code),
  status text not null default 'active',
  provider text not null default 'manual',
  period_start timestamptz not null default now(),
  period_end timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint subscriptions_status_chk check (status in ('active','cancelled','expired')),
  constraint subscriptions_provider_chk check (provider in ('manual','mock','zarinpal')),
  constraint subscriptions_period_chk check (period_end is null or period_end > period_start)
);
create unique index subscriptions_one_active_uq on public.subscriptions (shop_id) where status = 'active';
create index subscriptions_plan_idx on public.subscriptions (plan_code);

-- ---------------------------------------------------------------------
-- analytics_events: فقط از RPC نوشته می‌شود
-- ---------------------------------------------------------------------
create table public.analytics_events (
  id bigint generated always as identity primary key,
  shop_id uuid not null references public.shops (id) on delete cascade,
  event_type text not null,
  product_id uuid references public.products (id) on delete set null,
  session_id text not null,
  created_at timestamptz not null default now(),
  constraint analytics_type_chk check (event_type in ('shop_view','product_view','add_to_cart','checkout_start','purchase')),
  constraint analytics_session_fmt check (session_id ~ '^[A-Za-z0-9_-]{8,64}$')
);
create index analytics_shop_type_created_idx on public.analytics_events (shop_id, event_type, created_at);
create index analytics_product_idx on public.analytics_events (product_id) where product_id is not null;

-- ---------------------------------------------------------------------
-- store_links: لینک‌های صفحهٔ بیو (/@username)
-- ---------------------------------------------------------------------
create table public.store_links (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id) on delete cascade,
  type text not null,
  label text not null,
  url text not null,
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint store_links_type_chk check (type in ('shop','product','instagram','whatsapp','telegram','phone','website','custom')),
  constraint store_links_label_len check (char_length(label) between 1 and 60),
  constraint store_links_url_chk check (char_length(url) <= 500 and url ~* '^(https://|tel:|mailto:)')
);
create index store_links_shop_order_idx on public.store_links (shop_id, sort_order);

-- ---------------------------------------------------------------------
-- reports و admin_audit_log و app_settings
-- ---------------------------------------------------------------------
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid references public.profiles (id) on delete set null,
  target_type text not null,
  target_id uuid not null,
  reason text not null,
  contact text,
  status text not null default 'open',
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint reports_target_chk check (target_type in ('shop','product')),
  constraint reports_reason_len check (char_length(reason) between 3 and 1000),
  constraint reports_contact_len check (contact is null or char_length(contact) <= 100),
  constraint reports_status_chk check (status in ('open','reviewing','resolved','dismissed')),
  constraint reports_note_len check (admin_note is null or char_length(admin_note) <= 1000)
);
create index reports_status_idx on public.reports (status, created_at desc);
create index reports_target_idx on public.reports (target_type, target_id);
create index reports_reporter_idx on public.reports (reporter_id) where reporter_id is not null;

create table public.admin_audit_log (
  id bigint generated always as identity primary key,
  admin_id uuid references public.profiles (id) on delete set null,
  action text not null,
  target_type text,
  target_id text,
  created_at timestamptz not null default now()
);
create index admin_audit_admin_idx on public.admin_audit_log (admin_id) where admin_id is not null;
create index admin_audit_created_idx on public.admin_audit_log (created_at desc);

-- تنظیمات عمومی: همه می‌توانند بخوانند. هرگز Secret اینجا نگذار.
create table public.app_settings (
  key text primary key,
  value jsonb not null,
  description text,
  updated_at timestamptz not null default now()
);

-- جدول محدودیت نرخ (در schema خصوصی، از API در دسترس نیست)
create table private.rate_limits (
  bucket text not null,
  key text not null,
  window_start timestamptz not null,
  hits int not null default 0,
  primary key (bucket, key, window_start)
);
create index rate_limits_window_idx on private.rate_limits (window_start);

-- ---------------------------------------------------------------------
-- داده‌های پایه
-- قیمت پلن‌ها (تومان) نمونه است؛ بعداً با UPDATE روی جدول plans عوض کن.
-- ---------------------------------------------------------------------
insert into public.plans (code, name, price, max_products, max_orders_per_30d, can_use_coupons, analytics_level, features, sort_order) values
  ('free', 'رایگان', 0, 10, 30, false, 'none',
    '["فروشگاه و لینک بیو","تا ۱۰ محصول","تا ۳۰ سفارش در ۳۰ روز"]'::jsonb, 1),
  ('starter', 'استارتر', 99000, 100, null, true, 'basic',
    '["تا ۱۰۰ محصول","سفارش نامحدود","کد تخفیف","آمار پایه"]'::jsonb, 2),
  ('pro', 'حرفه‌ای', 249000, null, null, true, 'advanced',
    '["محصول نامحدود","سفارش نامحدود","کد تخفیف","آمار پیشرفته"]'::jsonb, 3);

insert into public.app_settings (key, value, description) values
  ('allow_mock_payments', 'true'::jsonb,
   'اجازهٔ پرداخت آزمایشی (Mock). قبل از راه‌اندازی واقعی حتماً false شود.');
