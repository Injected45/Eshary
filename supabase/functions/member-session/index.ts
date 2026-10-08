// Edge Function: member-session
//
// Exchanges verified codes for a Supabase session, without a password.
// Deploy from the Supabase dashboard (Edge Functions -> member-session -> paste
// this file -> Deploy). SUPABASE_URL, SUPABASE_ANON_KEY and
// SUPABASE_SERVICE_ROLE_KEY are provided to every function automatically;
// nothing else needs to be configured.
//
// The app calls the SQL function member_request_otp first (it checks the
// e-mail + phone pair, sends the WhatsApp code and says whether the e-mail must
// be proven too; the app then mails the e-mail code through Supabase Auth).
// Then this function:
//   1. checks the WhatsApp code (member_consume_otp, commit = false);
//   2. when this is the account's FIRST time (needsEmail), checks the e-mail
//      code with Supabase Auth, which proves the person owns the address;
//   3. marks the WhatsApp code used (commit = true) and binds the phone;
//   4. returns a one-time token the app exchanges for a session
//      (auth.verifyOTP(tokenHash, type: email)).
// Later sign-ins skip step 2: e-mail + linked phone + WhatsApp code.
//
// The service-role key never leaves this function.

import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, code: "bad_request" }, 405);

  try {
    const { email, phone, otp, emailCode } = await req.json();
    if (typeof email !== "string" || typeof phone !== "string" ||
        typeof otp !== "string") {
      return json({ ok: false, code: "bad_request" }, 400);
    }

    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const mail = email.trim().toLowerCase();
    const cleanPhone = phone.replace(/\s/g, "");

    // 1. WhatsApp code (a wrong one still counts an attempt, in the database).
    const { data: checked, error: rpcError } = await admin.rpc(
      "member_consume_otp",
      { p_email: mail, p_phone: cleanPhone, p_otp: otp, p_commit: false },
    );
    if (rpcError) return json({ ok: false, code: "server_error" }, 500);
    if (!checked?.ok) return json(checked);

    // 2. First time only: prove the e-mail with the code Supabase mailed.
    let userId: string | null = checked.userId ?? null;
    if (checked.needsEmail) {
      if (typeof emailCode !== "string" || emailCode.trim().length < 6) {
        return json({ ok: false, code: "invalid_email_code" });
      }
      // A throw-away client: its session is never stored or returned.
      const probe = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data: proof, error: proofError } = await probe.auth.verifyOtp({
        email: mail,
        token: emailCode.trim(),
        type: "email",
      });
      if (proofError || !proof?.user) {
        return json({ ok: false, code: "invalid_email_code" });
      }
      userId = proof.user.id;
    }

    // 3. Both proofs passed: burn the WhatsApp code and bind the phone.
    const { data: done, error: commitError } = await admin.rpc(
      "member_consume_otp",
      { p_email: mail, p_phone: cleanPhone, p_otp: otp, p_commit: true },
    );
    if (commitError) return json({ ok: false, code: "server_error" }, 500);
    if (!done?.ok) return json(done);
    userId = userId ?? done.userId ?? null;
    if (!userId) return json({ ok: false, code: "create_failed" }, 500);

    const { error: linkError } = await admin.rpc("member_link_phone", {
      p_user_id: userId,
      p_phone: cleanPhone,
    });
    if (linkError) return json({ ok: false, code: "link_failed" }, 500);

    // 4. One-time token the app turns into a session.
    const { data: link, error: linkGenError } =
      await admin.auth.admin.generateLink({ type: "magiclink", email: mail });
    const tokenHash = link?.properties?.hashed_token;
    if (linkGenError || !tokenHash) {
      return json({ ok: false, code: "link_failed" }, 500);
    }

    return json({ ok: true, tokenHash, isNew: checked.needsEmail === true });
  } catch (_e) {
    return json({ ok: false, code: "server_error" }, 500);
  }
});
