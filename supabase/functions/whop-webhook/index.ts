// ================================================================
// عقاري ديزاين — استقبال إشعارات الدفع من Whop وتفعيل الاشتراك تلقائياً
// تُنشر كـ Edge Function باسم whop-webhook (مع تعطيل Verify JWT)
//
// الأمان: المفتاح السري يُضبط كـSecret باسم WEBHOOK_KEY من لوحة Supabase
// (Edge Functions → Secrets) ولا يُكتب هنا أبداً — هذا الملف عام على GitHub.
// رابط الويبهوك في Whop: https://<PROJECT>.supabase.co/functions/v1/whop-webhook?key=<WEBHOOK_KEY>
// ================================================================
import { createClient } from "jsr:@supabase/supabase-js@2";

const WEBHOOK_KEY = Deno.env.get("WEBHOOK_KEY") ?? "";

Deno.serve(async (req) => {
  try {
    // التحقق من مفتاح الأمان في الرابط — يرفض كل شيء إن لم يُضبط السر
    const url = new URL(req.url);
    if (!WEBHOOK_KEY || url.searchParams.get("key") !== WEBHOOK_KEY) {
      return new Response("unauthorized", { status: 401 });
    }
    if (req.method !== "POST") {
      return new Response("ok", { status: 200 });
    }

    const body = await req.json();
    const action = String(body.action ?? body.event ?? body.type ?? "");

    // استخراج أول بريد إلكتروني من أي مكان في الحمولة
    // (يتحمل اختلاف شكل حمولات Whop بين الإصدارات)
    const emails: string[] = [];
    (function walk(o: unknown) {
      if (!o) return;
      if (typeof o === "string") {
        const m = o.match(/[\w.+-]+@[\w-]+\.[\w.-]+/);
        if (m) emails.push(m[0].toLowerCase());
      } else if (typeof o === "object") {
        for (const v of Object.values(o as Record<string, unknown>)) walk(v);
      }
    })(body);
    const email = emails[0];
    if (!email) return new Response("no email in payload", { status: 200 });

    // تحديد نوع الحدث: تفعيل أم إلغاء
    // أسماء الأحداث الفعلية في Whop: membership_activated / membership_deactivated / invoice_paid
    const activate = /payment[._]succeeded|went[._]valid|membership[._]activated|invoice[._]paid/i.test(action);
    const deactivate = /went[._]invalid|membership[._]deactivated/i.test(action);
    if (!activate && !deactivate) {
      return new Response("ignored action: " + action, { status: 200 });
    }

    const sb = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data, error } = await sb.rpc("set_subscription_by_email", {
      p_email: email,
      p_active: activate,
      p_days: 32,
      p_provider: "whop",
      p_ref: String(body?.data?.id ?? ""),
    });
    if (error) return new Response("rpc error: " + error.message, { status: 500 });
    return new Response("ok: " + data, { status: 200 });
  } catch (e) {
    return new Response("error: " + (e instanceof Error ? e.message : String(e)), { status: 400 });
  }
});
