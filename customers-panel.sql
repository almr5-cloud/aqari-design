-- ================================================================
-- عقاري ديزاين — تفعيل قسم «العملاء ونشاطهم» في لوحة الإحصاءات
-- كيف تشغّله: Supabase → SQL Editor → الصق هذا الملف كاملاً → Run
-- مرة واحدة فقط.
-- ================================================================

create or replace function public.get_stats(p_key text)
returns json language plpgsql security definer set search_path = public as $fn$
begin
  if p_key is distinct from 'PUT_YOUR_STATS_KEY_HERE' then
    return json_build_object('error','unauthorized');
  end if;
  return json_build_object(
    'visits_today',   (select count(*) from events where kind='visit' and created_at >= current_date),
    'visits_7d',      (select count(*) from events where kind='visit' and created_at >= now()-interval '7 days'),
    'visits_total',   (select count(*) from events where kind='visit'),
    'auth_open_7d',   (select count(*) from events where kind='auth_open' and created_at >= now()-interval '7 days'),
    'pay_click_7d',   (select count(*) from events where kind='pay_click' and created_at >= now()-interval '7 days'),
    'paywall_7d',     (select count(*) from events where kind='paywall' and created_at >= now()-interval '7 days'),
    'signups_7d',     (select count(*) from auth.users where created_at >= now()-interval '7 days'),
    'signups_total',  (select count(*) from auth.users),
    'subs_active',    (select count(*) from subscriptions where status='active'),
    'downloads_7d',   (select count(*) from downloads where created_at >= now()-interval '7 days'),
    'downloads_total',(select count(*) from downloads),

    'daily', (select coalesce(json_agg(t order by t.d),'[]'::json) from (
        select to_char(created_at::date,'MM-DD') as d, count(*) as n
        from events where kind='visit' and created_at >= now()-interval '14 days'
        group by created_at::date order by created_at::date) t),

    'sources', (select coalesce(json_agg(s order by s.n desc),'[]'::json) from (
        select coalesce(nullif(src,''),'مباشر') as src, count(*) as n
        from events where kind='visit' and created_at >= now()-interval '30 days'
        group by 1 order by 2 desc limit 8) s),

    'devices', (select coalesce(json_agg(v order by v.n desc),'[]'::json) from (
        select coalesce(nullif(device,''),'غير معروف') as src, count(*) as n
        from events where kind='visit' and created_at >= now()-interval '30 days'
        group by 1 order by 2 desc) v),

    'referrers', (select coalesce(json_agg(r order by r.n desc),'[]'::json) from (
        select coalesce(nullif(ref,''),'مباشر / واتساب') as src, count(*) as n
        from events where kind='visit' and created_at >= now()-interval '30 days'
        group by 1 order by 2 desc limit 8) r),

    -- 👥 قسم العملاء ونشاطهم
    'customers', (select coalesce(json_agg(c order by c.pro desc, c.joined desc),'[]'::json) from (
        select
          u.email                                   as email,
          u.created_at::date::text                  as joined,
          (coalesce(s.status,'') = 'active')        as pro,
          (select count(*) from downloads d where d.user_id = u.id)                        as downloads,
          (select max(d.created_at)::timestamp(0)::text from downloads d where d.user_id = u.id) as last_dl,
          (select count(*) from designs g where g.user_id = u.id)                          as designs,
          u.last_sign_in_at::timestamp(0)::text     as last_seen
        from auth.users u
        left join subscriptions s on s.user_id = u.id) c)
  );
end $fn$;

grant execute on function public.get_stats(text) to anon, authenticated;
