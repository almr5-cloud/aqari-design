-- ================================================================
-- عقاري ديزاين — جدول تتبّع التحميلات (لحد الباقة الشهري)
-- يُشغَّل مرة واحدة في SQL Editor على Supabase
-- ================================================================

create table if not exists public.downloads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists downloads_user_created
  on public.downloads (user_id, created_at desc);

alter table public.downloads enable row level security;

-- الوسيط يسجّل تحميلاته ويقرأ عددها فقط — لا يعدّل ولا يحذف
drop policy if exists "insert own downloads" on public.downloads;
create policy "insert own downloads" on public.downloads
  for insert
  with check (auth.uid() = user_id);

drop policy if exists "read own downloads" on public.downloads;
create policy "read own downloads" on public.downloads
  for select
  using (auth.uid() = user_id);
