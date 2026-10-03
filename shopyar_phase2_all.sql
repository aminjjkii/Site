
-- >>>>>>>>>> migrations/0001_schema.sql <<<<<<<<<<

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

-- >>>>>>>>>> migrations/0002_helpers_triggers.sql <<<<<<<<<<

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

-- >>>>>>>>>> migrations/0003_rpc.sql <<<<<<<<<<

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

-- >>>>>>>>>> migrations/0004_rls.sql <<<<<<<<<<

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

-- >>>>>>>>>> migrations/0005_storage.sql <<<<<<<<<<

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
