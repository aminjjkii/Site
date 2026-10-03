-- =====================================================================
-- ShopYar | seed.sql  (فقط برای محیط تست!)
-- سه فروشندهٔ نمونه با رمز عمومی و شناخته‌شده می‌سازد.
-- هرگز روی پروژهٔ واقعی (Production) اجرا نکن.
-- یک بار اجرا کن. برای پاک کردن، بلوک آخر فایل را اجرا کن.
--
-- حساب‌ها (رمز همه: ShopYar-Demo-123):
--   demo.fashion@shopyar.test      فروشگاه پوشاک   /shop/demo_fashion
--   demo.mobile@shopyar.test       لوازم جانبی موبایل /shop/demo_mobile
--   demo.beauty@shopyar.test       زیبایی و آرایشی /shop/demo_beauty
-- شمارهٔ کارت نمونه ساختگی است و کارت واقعی نیست.
-- =====================================================================

-- ۱) کاربران Auth (توکن‌ها باید رشتهٔ خالی باشند، نه null)
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, last_sign_in_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
       crypt('ShopYar-Demo-123', gen_salt('bf')), now(), now(),
       '{"provider":"email","providers":["email"]}'::jsonb,
       jsonb_build_object('full_name', u.full_name), now(), now(), '', '', '', ''
  from (values
    ('a0000000-0000-4000-8000-000000000001'::uuid, 'demo.fashion@shopyar.test', 'آرین نمونه'),
    ('a0000000-0000-4000-8000-000000000002'::uuid, 'demo.mobile@shopyar.test', 'مهدی نمونه'),
    ('a0000000-0000-4000-8000-000000000003'::uuid, 'demo.beauty@shopyar.test', 'سارا نمونه')
  ) as u(id, email, full_name);

insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id, u.id::text,
       jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
       'email', now(), now(), now()
  from auth.users u
 where u.email like '%@shopyar.test';

-- ۲) فروشگاه‌ها (Trigger اشتراک رایگان و تنظیمات پرداخت را می‌سازد)
insert into public.shops (id, owner_id, username, name, description, category, instagram, phone, shipping_fee, free_shipping_over) values
  ('b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'demo_fashion',
   'مد و پوشاک آرین', 'پوشاک روزمره با ارسال به سراسر ایران', 'پوشاک', 'demo_fashion', '09120000000', 60000, 1500000),
  ('b0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000002', 'demo_mobile',
   'لوازم جانبی مهدی', 'قاب، کابل، پاوربانک و هندزفری اورجینال', 'موبایل و لوازم جانبی', 'demo_mobile', '09120000001', 50000, 1000000),
  ('b0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000003', 'demo_beauty',
   'زیبایی سارا', 'محصولات مراقبت پوست و آرایشی', 'زیبایی و سلامت', 'demo_beauty', '09120000002', 45000, 1200000);

update public.shop_payment_settings
   set card_enabled = true, card_number = '6037990000000000', card_holder = 'نمونهٔ آزمایشی', online_provider = 'mock'
 where shop_id in (
   'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000002',
   'b0000000-0000-4000-8000-000000000003');

-- فروشگاه پوشاک پلن استارتر دارد تا کد تخفیف داشته باشد
update public.subscriptions set plan_code = 'starter' where shop_id = 'b0000000-0000-4000-8000-000000000001';

-- ۳) دسته‌بندی‌ها
insert into public.categories (shop_id, name, slug, sort_order) values
  ('b0000000-0000-4000-8000-000000000001', 'بالاپوش و تی‌شرت', 'tops', 1),
  ('b0000000-0000-4000-8000-000000000001', 'شلوار و اکسسوری', 'bottoms', 2),
  ('b0000000-0000-4000-8000-000000000002', 'محافظ و قاب', 'cases', 1),
  ('b0000000-0000-4000-8000-000000000002', 'شارژ و صوتی', 'power-audio', 2),
  ('b0000000-0000-4000-8000-000000000003', 'مراقبت پوست', 'skincare', 1),
  ('b0000000-0000-4000-8000-000000000003', 'عطر و ماسک', 'fragrance-mask', 2);

-- ۴) محصولات (بدون عکس؛ رابط کاربری تصویر جایگزین نشان می‌دهد)
insert into public.products (shop_id, category_id, title, description, price, discount_price, stock, sku, featured)
select v.shop_id::uuid,
       (select c.id from public.categories c where c.shop_id = v.shop_id::uuid and c.slug = v.cat),
       v.title, v.descr, v.price, v.disc, v.stock, v.sku, v.feat
  from (values
    ('b0000000-0000-4000-8000-000000000001', 'tops', 'تی‌شرت نخی ساده', 'تی‌شرت نخی دو رشته، مناسب فصل‌های گرم', 450000, 390000, 0, 'TS-001', true),
    ('b0000000-0000-4000-8000-000000000001', 'bottoms', 'شلوار جین راسته', 'جین ضخیم و مقاوم با دوخت دوبل', 1250000, null, 0, 'JN-001', true),
    ('b0000000-0000-4000-8000-000000000001', 'tops', 'مانتو کتان', 'مانتو کتان سبک مناسب بهار و تابستان', 1890000, null, 8, 'MT-001', false),
    ('b0000000-0000-4000-8000-000000000001', 'bottoms', 'شال نخی', 'شال نخی نرم در چند رنگ', 320000, null, 15, 'SC-001', false),
    ('b0000000-0000-4000-8000-000000000001', 'bottoms', 'کیف دوشی', 'کیف دوشی چرم مصنوعی (ناموجود نمونه)', 980000, null, 0, 'BG-001', false),
    ('b0000000-0000-4000-8000-000000000002', 'cases', 'قاب سیلیکونی', 'قاب سیلیکونی ضد ضربه', 180000, null, 40, 'CS-001', false),
    ('b0000000-0000-4000-8000-000000000002', 'power-audio', 'کابل شارژ تایپ‌سی', 'کابل فست‌شارژ یک‌متری', 150000, 120000, 60, 'CB-001', true),
    ('b0000000-0000-4000-8000-000000000002', 'power-audio', 'پاوربانک ۱۰۰۰۰ میلی‌آمپر', 'پاوربانک با دو خروجی', 890000, null, 12, 'PB-001', true),
    ('b0000000-0000-4000-8000-000000000002', 'power-audio', 'هندزفری بلوتوث', 'هندزفری بی‌سیم با باتری ۸ ساعته', 1450000, null, 3, 'HF-001', false),
    ('b0000000-0000-4000-8000-000000000003', 'skincare', 'کرم مرطوب‌کننده', 'کرم مرطوب‌کنندهٔ روزانه برای پوست‌های معمولی', 520000, null, 25, 'KR-001', true),
    ('b0000000-0000-4000-8000-000000000003', 'skincare', 'سرم ویتامین سی', 'سرم روشن‌کنندهٔ پوست', 780000, null, 9, 'SR-001', true),
    ('b0000000-0000-4000-8000-000000000003', 'fragrance-mask', 'ماسک صورت', 'ماسک ورقه‌ای مرطوب‌کننده', 95000, null, 50, 'MS-001', false),
    ('b0000000-0000-4000-8000-000000000003', 'fragrance-mask', 'عطر جیبی', 'عطر جیبی ۳۰ میلی‌لیتری', 640000, null, 2, 'AT-001', false)
  ) as v(shop_id, cat, title, descr, price, disc, stock, sku, feat);

-- ۵) Variantها (موجودی محصول به‌طور خودکار از جمع آن‌ها حساب می‌شود)
-- مثال: مشکی/M = ۵ ، مشکی/L = ۲ ، سفید/M = ۰ ، سفید/L = ۴
insert into public.product_variants (product_id, shop_id, attributes, stock, sort_order)
select p.id, p.shop_id, x.attrs::jsonb, x.stock, x.ord
  from public.products p
  join (values
    ('TS-001', '{"رنگ":"مشکی","سایز":"M"}', 5, 1),
    ('TS-001', '{"رنگ":"مشکی","سایز":"L"}', 2, 2),
    ('TS-001', '{"رنگ":"سفید","سایز":"M"}', 0, 3),
    ('TS-001', '{"رنگ":"سفید","سایز":"L"}', 4, 4),
    ('JN-001', '{"سایز":"30"}', 3, 1),
    ('JN-001', '{"سایز":"32"}', 6, 2),
    ('JN-001', '{"سایز":"34"}', 4, 3)
  ) as x(sku, attrs, stock, ord)
    on x.sku = p.sku
 where p.shop_id = 'b0000000-0000-4000-8000-000000000001';

-- ۶) کد تخفیف نمونه و لینک‌های بیو
insert into public.coupons (shop_id, code, discount_type, discount_value, minimum_order, maximum_discount, expires_at, usage_limit)
values ('b0000000-0000-4000-8000-000000000001', 'WELCOME10', 'percentage', 10, 200000, 100000, now() + interval '90 days', 100);

insert into public.store_links (shop_id, type, label, url, sort_order) values
  ('b0000000-0000-4000-8000-000000000001', 'instagram', 'اینستاگرام', 'https://instagram.com/demo_fashion', 1),
  ('b0000000-0000-4000-8000-000000000001', 'phone', 'تماس با ما', 'tel:+989120000000', 2);

-- ۷) دو سفارش نمونه از طریق خود place_order (برای دیدن داشبورد)
-- اگر این بخش خطا بدهد، بقیهٔ داده‌ها حفظ می‌شود و فقط پیام هشدار می‌آید.
do $$
declare
  v_shop uuid := 'b0000000-0000-4000-8000-000000000001';
  v_ts uuid;
  v_ts_var uuid;
  v_sc uuid;
  v_r jsonb;
begin
  select p.id into v_ts from public.products p where p.shop_id = v_shop and p.sku = 'TS-001';
  select v.id into v_ts_var from public.product_variants v
   where v.product_id = v_ts and v.attributes = '{"رنگ":"مشکی","سایز":"M"}'::jsonb;
  select p.id into v_sc from public.products p where p.shop_id = v_shop and p.sku = 'SC-001';

  -- سفارش ۱: کارت‌به‌کارت با کد تخفیف؛ پرداخت تأیید می‌شود
  v_r := public.place_order(
    v_shop,
    jsonb_build_array(
      jsonb_build_object('product_id', v_ts, 'variant_id', v_ts_var, 'quantity', 1),
      jsonb_build_object('product_id', v_sc, 'quantity', 2)),
    'سارا احمدی', '09120000011', 'تهران', 'تهران',
    'خیابان نمونه، کوچهٔ آزمایشی، پلاک ۱۲', '1234567890', 'لطفاً قبل از ارسال تماس بگیرید',
    'card_to_card', 'WELCOME10', 'seedsession01');
  update public.payments set status = 'paid', paid_at = now()
   where order_id = (v_r ->> 'order_id')::uuid;

  -- سفارش ۲: پرداخت آنلاین آزمایشی؛ در انتظار پرداخت می‌ماند
  v_r := public.place_order(
    v_shop,
    jsonb_build_array(jsonb_build_object('product_id', v_sc, 'quantity', 1)),
    'علی رضایی', '09120000022', 'اصفهان', 'اصفهان',
    'میدان نمونه، خیابان آزمایشی، پلاک ۵', '8123456789', null,
    'online', null, 'seedsession02');
exception when others then
  raise notice 'سفارش‌های نمونه ساخته نشد: %', sqlerrm;
end
$$;

-- =====================================================================
-- پاک کردن همهٔ دادهٔ نمونه (اجرای دستی؛ همه‌چیز به‌صورت آبشاری پاک می‌شود):
-- delete from auth.users where email like '%@shopyar.test';
-- =====================================================================
