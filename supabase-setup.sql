-- ================================================================
-- عقاري ديزاين — إعداد قاعدة البيانات على Supabase
-- كيف تشغّله: افتح مشروعك في supabase.com → SQL Editor →
-- الصق هذا الملف كاملاً → اضغط Run. مرة واحدة فقط.
-- ================================================================

-- جدول ملفات الوسطاء (يرتبط بحساب المستخدم في نظام الدخول)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  agent_name text,
  phone text,
  updated_at timestamptz not null default now()
);

-- جدول التصاميم المحفوظة (كل تصميم: اسم + كل الإعدادات كـ JSON)
create table if not exists public.designs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  data jsonb not null,
  created_at timestamptz not null default now()
);

create index if not exists designs_user_created
  on public.designs (user_id, created_at desc);

-- ================================================================
-- الأمان: كل وسيط يرى ويعدّل بياناته فقط (Row Level Security)
-- ================================================================
alter table public.profiles enable row level security;
alter table public.designs  enable row level security;

drop policy if exists "own profile" on public.profiles;
create policy "own profile" on public.profiles
  for all
  using (auth.uid() = id)
  with check (auth.uid() = id);

drop policy if exists "own designs" on public.designs;
create policy "own designs" on public.designs
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
