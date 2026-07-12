-- ================================================================
-- عقاري ديزاين — جدول الاشتراكات (خطة مجانية / Pro بـ49 ريال شهرياً)
-- يُشغَّل مرة واحدة في SQL Editor على Supabase
-- ================================================================

create table if not exists public.subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  plan text not null default 'free',              -- free | pro
  status text not null default 'inactive',        -- active | inactive | canceled
  provider text,                                   -- stripe | moyasar | manual
  provider_ref text,                               -- معرف العملية لدى بوابة الدفع
  current_period_end timestamptz,                  -- نهاية فترة الاشتراك الحالية
  updated_at timestamptz not null default now()
);

alter table public.subscriptions enable row level security;

-- الوسيط يقرأ اشتراكه فقط — ولا يستطيع تعديله بنفسه
-- (التفعيل يتم من لوحة Supabase أو من Webhook بوابة الدفع بمفتاح service_role)
drop policy if exists "read own subscription" on public.subscriptions;
create policy "read own subscription" on public.subscriptions
  for select
  using (auth.uid() = user_id);

-- ================================================================
-- للتفعيل اليدوي من لوحة Supabase (Table Editor أو SQL):
-- insert into public.subscriptions (user_id, plan, status, provider, current_period_end)
-- values ('UUID-الوسيط', 'pro', 'active', 'manual', now() + interval '30 days')
-- on conflict (user_id) do update
--   set plan='pro', status='active', current_period_end=now() + interval '30 days', updated_at=now();
-- ================================================================
