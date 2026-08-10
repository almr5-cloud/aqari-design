-- ================================================================
-- عقاري ديزاين — دالة لوحة الإحصاءات
-- كيف تشغّله: Supabase → SQL Editor → الصق هذا الملف كاملاً → Run
--
-- ⚠️ استبدل PUT_YOUR_STATS_KEY_HERE بمفتاحك قبل التشغيل.
--    لا تحفظ المفتاح في هذا الملف — المستودع عام.
--
-- 🧹 استبعاد الضجيج: زياراتك أنت وزيارات التطوير تُوسم بمصدر 'internal'
--    (افتح الموقع مرة بـ ?internal=1 على كل جهاز تستخدمه)، و'test-run'
--    للاختبارات الآلية. الدالة تستبعدهما من كل الأرقام، وترجع عددهما
--    منفصلاً في internal_excluded حتى تتأكد أن الاستبعاد يعمل.
-- ================================================================

create or replace function public.get_stats(p_key text)
returns json language plpgsql security definer set search_path = public as $fn$
declare
  noise text[] := array['internal', 'test-run'];
  -- حسابات داخلية لا تُحتسب كعملاء (حسابك أنت + حسابات التشخيص)
  internal_users uuid[];
begin
  if p_key is distinct from 'PUT_YOUR_STATS_KEY_HERE' then
    return json_build_object('error','unauthorized');
  end if;

  select coalesce(array_agg(id), '{}')
    into internal_users
    from auth.users
   where email ilike '%@aqaridesign.com'
      or email = 'technical55102@gmail.com';

  return json_build_object(
    'visits_today',   (select count(*) from events where kind='visit' and not (src = any(noise)) and created_at >= current_date),
    'visits_7d',      (select count(*) from events where kind='visit' and not (src = any(noise)) and created_at >= now()-interval '7 days'),
    'visits_total',   (select count(*) from events where kind='visit' and not (src = any(noise))),
    'app_open_7d',    (select count(*) from events where kind='app_open' and not (src = any(noise)) and created_at >= now()-interval '7 days'),
    'auth_open_7d',   (select count(*) from events where kind='auth_open' and not (src = any(noise)) and created_at >= now()-interval '7 days'),
    'pay_click_7d',   (select count(*) from events where kind='pay_click' and not (src = any(noise)) and created_at >= now()-interval '7 days'),
    'paywall_7d',     (select count(*) from events where kind='paywall'  and not (src = any(noise)) and created_at >= now()-interval '7 days'),
    'support_7d',     (select count(*) from events where kind in ('support_open','support_click') and not (src = any(noise)) and created_at >= now()-interval '7 days'),

    -- كم زيارة استُبعدت (تأكيد أن الفلتر يعمل)
    'internal_excluded_7d', (select count(*) from events where kind='visit' and src = any(noise) and created_at >= now()-interval '7 days'),

    'signups_7d',     (select count(*) from auth.users where created_at >= now()-interval '7 days' and not (id = any(internal_users))),
    'signups_total',  (select count(*) from auth.users where not (id = any(internal_users))),
    'subs_active',    (select count(*) from subscriptions s where s.status='active' and not (s.user_id = any(internal_users))),
    'downloads_7d',   (select count(*) from downloads d where d.created_at >= now()-interval '7 days' and not (d.user_id = any(internal_users))),
    'downloads_total',(select count(*) from downloads d where not (d.user_id = any(internal_users))),

    'daily', (select coalesce(json_agg(t order by t.d),'[]'::json) from (
        select to_char(created_at::date,'MM-DD') as d, count(*) as n
        from events where kind='visit' and not (src = any(noise)) and created_at >= now()-interval '14 days'
        group by created_at::date order by created_at::date) t),

    'sources', (select coalesce(json_agg(s order by s.n desc),'[]'::json) from (
        select coalesce(nullif(src,''),'مباشر') as src, count(*) as n
        from events where kind='visit' and not (src = any(noise)) and created_at >= now()-interval '30 days'
        group by 1 order by 2 desc limit 8) s),

    'devices', (select coalesce(json_agg(v order by v.n desc),'[]'::json) from (
        select coalesce(nullif(device,''),'غير معروف') as src, count(*) as n
        from events where kind='visit' and not (src = any(noise)) and created_at >= now()-interval '30 days'
        group by 1 order by 2 desc) v),

    'referrers', (select coalesce(json_agg(r order by r.n desc),'[]'::json) from (
        select coalesce(nullif(ref,''),'مباشر / واتساب') as src, count(*) as n
        from events where kind='visit' and not (src = any(noise)) and created_at >= now()-interval '30 days'
        group by 1 order by 2 desc limit 8) r),

    -- 👥 قسم العملاء ونشاطهم — بلا الحسابات الداخلية
    'customers', (select coalesce(json_agg(c order by c.pro desc, c.joined desc),'[]'::json) from (
        select
          u.email                                   as email,
          u.created_at::date::text                  as joined,
          (coalesce(s.status,'') = 'active')        as pro,
          (select count(*) from downloads d where d.user_id = u.id)                        as downloads,
          (select max(d.created_at)::timestamp(0)::text from downloads d where d.user_id = u.id) as last_dl,
          (select count(*) from designs g where g.user_id = u.id)                          as designs,
          greatest(
            u.last_sign_in_at,
            (select max(e.created_at) from events e where e.user_id = u.id)
          )::timestamp(0)::text                     as last_seen
        from auth.users u
        left join subscriptions s on s.user_id = u.id
        where not (u.id = any(internal_users))) c)
  );
end $fn$;

grant execute on function public.get_stats(text) to anon, authenticated;
