// ================================================================
// عقاري ديزاين — استقبال إشعارات الدفع من Whop وتفعيل الاشتراك تلقائياً
// تُنشر كـ Edge Function باسم whop-webhook (مع تعطيل Verify JWT)
//
// ⚠️ هذا الملف يجب أن يطابق النسخة المنشورة في Supabase.
//    كان قديماً في وقت من الأوقات وكاد يعيد عطلاً كلّف أول عميل — إن عدّلت
//    الدالة من لوحة Supabase، حدّث هذا الملف في نفس اليوم.
//
// الأمان: المفتاح السري يُضبط كـSecret باسم WEBHOOK_KEY من لوحة Supabase
// (Edge Functions → Secrets) ولا يُكتب هنا أبداً — هذا الملف عام على GitHub.
//
// رابط الويبهوك المطلوب في Whop (بالمسار والمفتاح كاملين):
//   https://pjhafrhjmvyirrcmnrhc.supabase.co/functions/v1/whop-webhook?key=<WEBHOOK_KEY>
//
// ⚠️ تحذير من فخ سابق: لا تستخدم رموز الهروب (\w، \.) في التعبيرات النمطية هنا.
//    لصقُها عبر أدوات وسيطة كسرها مرة، فصار البريد لا يُستخرج أبداً وتُهمل
//    كل الإشعارات بصمت. استُبدلت بأصناف أحرف صريحة [A-Za-z0-9] و [.]
// ================================================================
import { createClient } from "jsr:@supabase/supabase-js@2";

const WEBHOOK_KEY = Deno.env.get("WEBHOOK_KEY") ?? "";

// بلا رموز هروب — مقصود (انظر التحذير أعلاه)
const EMAIL_RE = /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+[.][A-Za-z0-9.-]+/;

Deno.serve(async (req) => {
  let action = "";
  let email: string | undefined;
  let result = "";
  let payload: unknown = null;

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
    payload = body;
    action = String(body.action ?? body.event ?? body.type ?? "");

    // استخراج أول بريد إلكتروني من أي مكان في الحمولة
    // (يتحمل اختلاف شكل حمولات Whop بين الإصدارات)
    const emails: string[] = [];
    (function walk(o: unknown) {
      if (!o) return;
      if (typeof o === "string") {
        const m = o.match(EMAIL_RE);
        if (m) emails.push(m[0].toLowerCase());
      } else if (typeof o === "object") {
        for (const v of Object.values(o as Record<string, unknown>)) walk(v);
      }
    })(body);
    email = emails[0];

    // تحديد نوع الحدث — أسماء Whop تختلف بين الإصدارات، فنقبل الصيغ كلها
    const activate = /payment[._-]?succeeded|payment[._-]?success|went[._-]?valid|membership[._-]?activated|membership[._-]?created|invoice[._-]?paid|subscription[._-]?created|subscription[._-]?activated/i
      .test(action);
    const deactivate = /went[._-]?invalid|membership[._-]?deactivated|membership[._-]?cancelled|membership[._-]?canceled|subscription[._-]?cancelled|expired|terminated/i
      .test(action);

    if (!email) {
      result = "NO_EMAIL_IN_PAYLOAD | action=" + action;
    } else if (!activate && !deactivate) {
      result = "IGNORED_ACTION: " + action + " | email=" + email;
    } else {
      const sb = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      );
      const { data, error } = await sb.rpc("set_subscription_by_email", {
        p_email: email,
        p_active: activate,
        p_days: 32,
        p_provider: "whop",
        p_ref: String((body as { data?: { id?: string } })?.data?.id ?? ""),
      });
      result = error
        ? "RPC_ERROR: " + error.message
        : "OK: " + (activate ? "activated:" : "deactivated:") + data;
    }
  } catch (e) {
    result = "EXCEPTION: " + (e instanceof Error ? e.message : String(e));
  }

  // تسجيل كل إشعار مهما كانت نتيجته — هذا ما يجعل التشخيص ممكناً لاحقاً
  try {
    const sb = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    await sb.from("webhook_log").insert({
      action,
      found_email: email ?? null,
      result,
      payload,
    });
  } catch (_) { /* التسجيل لا يجب أن يُفشل الاستجابة */ }

  // نرجع 200 دائماً حتى لا يعيد Whop المحاولة بلا فائدة
  return new Response(result || "ok", { status: 200 });
});
