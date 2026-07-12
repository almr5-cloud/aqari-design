-- ================================================================
-- عقاري ديزاين — دالة تفعيل/إلغاء الاشتراك بالبريد الإلكتروني
-- تُستدعى من Edge Function الخاصة بـWhop فقط (service_role)
-- تُشغَّل مرة واحدة في SQL Editor
-- ================================================================

create or replace function public.set_subscription_by_email(
  p_email text,
  p_active boolean,
  p_days int default 32,
  p_provider text default 'whop',
  p_ref text default null
) returns text
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid;
begin
  select id into v_uid from auth.users where lower(email) = lower(p_email) limit 1;
  if v_uid is null then
    return 'user_not_found:' || p_email;
  end if;

  insert into public.subscriptions
    (user_id, plan, status, provider, provider_ref, current_period_end, updated_at)
  values (
    v_uid, 'pro',
    case when p_active then 'active' else 'canceled' end,
    p_provider, p_ref,
    case when p_active then now() + make_interval(days => p_days) else now() end,
    now()
  )
  on conflict (user_id) do update set
    plan               = 'pro',
    status             = case when p_active then 'active' else 'canceled' end,
    provider           = excluded.provider,
    provider_ref       = coalesce(excluded.provider_ref, subscriptions.provider_ref),
    current_period_end = case when p_active then now() + make_interval(days => p_days) else now() end,
    updated_at         = now();

  return (case when p_active then 'activated:' else 'deactivated:' end) || v_uid::text;
end
$fn$;

-- الأمان: لا يستدعيها إلا الخادم (service_role) — تُمنع عن الزوار والمسجلين
revoke execute on function public.set_subscription_by_email(text, boolean, int, text, text) from public;
revoke execute on function public.set_subscription_by_email(text, boolean, int, text, text) from anon;
revoke execute on function public.set_subscription_by_email(text, boolean, int, text, text) from authenticated;
grant  execute on function public.set_subscription_by_email(text, boolean, int, text, text) to service_role;
