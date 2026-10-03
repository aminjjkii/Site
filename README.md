# ShopYar | فاز ۲: دیتابیس Supabase

## چی داخلشه
| فایل | کار |
|---|---|
| `migrations/0001_schema.sql` | ۲۱ جدول، قیدها، ایندکس‌ها، پلن‌ها (free/starter/pro) و تنظیمات |
| `migrations/0002_helpers_triggers.sql` | توابع کمکی، Triggerها، سقف پلن، همگام‌سازی موجودی و پرداخت |
| `migrations/0003_rpc.sql` | توابع قابل‌فراخوانی از فرانت (ثبت سفارش، پیگیری، کوپن، داشبورد...) |
| `migrations/0004_rls.sql` | دسترسی‌ها و سیاست‌های RLS |
| `migrations/0005_storage.sql` | Bucketها (avatars، shop-logos، product-images) و سیاست‌ها |
| `seed.sql` | دادهٔ آزمایشی (فقط تست!) |
| `shopyar_phase2_all.sql` | همان ۵ فایل پشت‌سرهم، برای یک‌جا چسباندن |

## اجرا (۳ قدم)
1. توی Supabase یک پروژهٔ **جدید** بساز (نه Peyk). نسخهٔ Postgres باید **۱۵ یا بالاتر** باشد (Settings ← Infrastructure).
2. **SQL Editor ← New query**، کل `shopyar_phase2_all.sql` را بچسبان و **Run** بزن. اگر خطا بدهد، اسکریپت کامل برمی‌گردد و چیزی نصفه نمی‌ماند. متن خطا را برای من بفرست.
3. بررسی:
```sql
select count(*) from information_schema.tables where table_schema = 'public';  -- باید ۲۱ باشد
select tablename from pg_tables where schemaname = 'public' and not rowsecurity;  -- باید خالی باشد
select code, name, price from public.plans order by sort_order;  -- سه پلن
```
اختیاری (فقط پروژهٔ تست): `seed.sql` را هم اجرا کن تا سه فروشگاه نمونه و دو سفارش بسازد. رمز همهٔ حساب‌های نمونه `ShopYar-Demo-123` است.

## ساخت Admin
اول با ایمیل خودت در Authentication ثبت‌نام کن، بعد:
```sql
update public.profiles set role = 'admin'
 where id = (select id from auth.users where email = 'YOUR_EMAIL');
```
نقش را کاربر از طریق API نمی‌تواند عوض کند؛ فقط از SQL Editor.

## قبل از راه‌اندازی واقعی
```sql
update public.app_settings set value = 'false'::jsonb where key = 'allow_mock_payments';
```
تا پرداخت آزمایشی (Mock) در محیط واقعی کار نکند. در همان حالت، کارت‌به‌کارت واقعی کار می‌کند.

## توابع (RPC)
| تابع | دسترسی | کار |
|---|---|---|
| `place_order` | همه | ثبت سفارش؛ قیمت، موجودی، کوپن و ارسال سمت سرور حساب می‌شود |
| `validate_coupon` | همه | بررسی کد تخفیف برای سبد |
| `track_order` | همه | پیگیری با شمارهٔ سفارش + ۴ رقم آخر موبایل |
| `submit_payment_receipt` | همه | مشتری شمارهٔ پیگیری واریز را ثبت می‌کند |
| `track_event` | همه | ثبت بازدید، افزودن به سبد، شروع پرداخت |
| `check_username_available` | همه | آزاد بودن username در Onboarding |
| `report_content` | همه | گزارش تخلف فروشگاه یا محصول |
| `confirm_payment` | وارد‌شده | تأیید واریز کارت‌به‌کارت توسط فروشنده |
| `mark_refunded` | وارد‌شده | ثبت بازپرداخت سفارش لغوشده |
| `seller_dashboard` | وارد‌شده | آمار داشبورد در یک فراخوانی |

کدهای خطا در ابتدای `0003_rpc.sql` فهرست شده‌اند؛ در فاز ۳ به پیام فارسی نگاشت می‌شوند.

## واقعی و Mock در این فاز
**واقعی:** همهٔ جدول‌ها، RLS، سقف پلن، ثبت سفارش، موجودی، کوپن، لغو و بازگشت موجودی، کارت‌به‌کارت، Storage، آمار داشبورد.
**Mock:** درگاه آنلاین (`online_provider = 'mock'`، فقط وقتی `allow_mock_payments` برابر true باشد)، پرداخت اشتراک (فاز ۱۴).

## تفاوت با طرح فاز ۱ (عمدی)
- ترتیب فایل‌ها: توابع قبل از RLS آمدند، چون Policyها به آن‌ها وابسته‌اند.
- `seed.sql` از migrations جدا شد، چون حساب‌هایی با رمز شناخته‌شده می‌سازد و نباید روی Production اجرا شود.
- سقف سفارش پلن‌ها «۳۰ روز اخیر» (پنجرهٔ لغزان) است، نه ماه تقویمی: ستون `max_orders_per_30d`.
- توابع Admin، آمار تحلیلی (`seller_analytics`) و تغییر پلن Mock در migrationهای فازهای ۱۲ تا ۱۴ اضافه می‌شوند.

## محدودیت‌های شناخته‌شده
- این اسکریپت‌ها روی Postgres واقعی اجرا نشده‌اند (محیط من Postgres ندارد). فقط ساختار و ارجاع‌ها بررسی شده. اولین اجرا آزمون واقعی است؛ هر خطایی را بفرست تا همان لحظه درست کنم.
- در `place_order`، درخواست‌های ناموفق در شمارندهٔ محدودیت نرخ ثبت نمی‌شوند (چون تراکنش برمی‌گردد). برای جلوگیری از سفارش جعلی انبوه، در فاز ۱۶ Captcha (Cloudflare Turnstile) اضافه می‌کنیم.
- پاک‌سازی فایل‌های یتیم Storage و داده‌های قدیمی: تابع `private.purge_old_data()` آماده است؛ زمان‌بندی آن با pg_cron اختیاری است (دستورش در `0002`).

## تست سریع RLS (بعد از seed)
فروشندهٔ دوم نباید سفارش‌های فروشندهٔ اول را ببیند:
```sql
begin;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select count(*) from public.orders;   -- باید 0 باشد
rollback;
```
