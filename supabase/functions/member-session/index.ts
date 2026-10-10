// Edge Function: member-session
//
// Turns a verified WhatsApp code into a Supabase session, without a password.
// Deploy from the Supabase dashboard (Edge Functions -> open the function ->
// Code -> paste this file -> Deploy). SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY are provided to every function automatically;
// nothing else needs to be configured.
//
// Two entrances (the body's `action`):
//
//   "activate"  a new subscriber whose trial request was approved:
//               { followToken, code }. The code is checked in the database,
//               the account is created once (internal e-mail, never shown),
//               and the trial STARTS here, in one database transaction
//               (trial_activate). Nothing the phone says about time is used.
//   "login"     an existing subscriber on a new device: { phone, code }.
//               It never touches the subscription.
//
// The WhatsApp codes live in the database as a keyed hash (HMAC with a server
// secret); this function never sees them. It returns a one-time token the app
// turns into a session (auth.verifyOTP(tokenHash, type: email)). The
// service-role key never leaves this function. No SMS is ever sent.

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
    const body = await req.json();
    const action = typeof body.action === "string" ? body.action : "";
    const code = body.code;
    if (typeof code !== "string") {
      return json({ ok: false, code: "bad_request" }, 400);
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );

    // The caller's network address, for the per-address limits in the database
    // (only a hash is stored there).
    const ip = (req.headers.get("cf-connecting-ip") ??
      req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim();

    // One-time token the app turns into a session.
    const issueToken = async (mail: string) => {
      const { data: link, error } = await admin.auth.admin.generateLink({
        type: "magiclink",
        email: mail,
      });
      const tokenHash = link?.properties?.hashed_token;
      return error || !tokenHash ? null : tokenHash;
    };

    // ------------------------------------------------------------------
    // Activation of an approved trial
    // ------------------------------------------------------------------
    if (action === "activate") {
      const followToken = body.followToken;
      if (typeof followToken !== "string") {
        return json({ ok: false, code: "bad_request" }, 400);
      }

      // 1. Is the request approved, still valid, and who is it?
      const { data: prep, error: prepError } = await admin.rpc("trial_prepare", {
        p_token: followToken,
      });
      if (prepError) return json({ ok: false, code: "server_error" }, 500);
      if (!prep?.ok) return json(prep);

      // 2. The code (a wrong one counts an attempt in the database); nothing
      //    is consumed and no account exists yet.
      const { data: checked, error: checkError } = await admin.rpc(
        "trial_activate",
        {
          p_token: followToken,
          p_code: code,
          p_user: "00000000-0000-0000-0000-000000000000",
          p_ip: ip,
          p_commit: false,
        },
      );
      if (checkError) return json({ ok: false, code: "server_error" }, 500);
      if (!checked?.ok) return json(checked);

      // 3. The account (created once; a retry after a failure finds it).
      const mail: string = prep.email;
      const { data: existing } = await admin.rpc("member_user_id_by_email", {
        p_email: mail,
      });
      let userId: string | null = existing ?? null;
      if (!userId) {
        const { data: made, error: createError } =
          await admin.auth.admin.createUser({
            email: mail,
            email_confirm: true,
            user_metadata: { full_name: prep.manager },
          });
        if (createError || !made?.user) {
          return json({
            ok: false,
            code: "create_failed",
            detail: createError?.message ?? "no user",
          }, 500);
        }
        userId = made.user.id;
      }

      // 4. The activation itself: code burned, trial start and end fixed by
      //    the database clock, all or nothing.
      const { data: done, error: doneError } = await admin.rpc(
        "trial_activate",
        {
          p_token: followToken,
          p_code: code,
          p_user: userId,
          p_ip: ip,
          p_commit: true,
        },
      );
      if (doneError) return json({ ok: false, code: "server_error" }, 500);
      if (!done?.ok) return json(done);

      const tokenHash = await issueToken(mail);
      if (!tokenHash) return json({ ok: false, code: "link_failed" }, 500);
      return json({ ok: true, tokenHash, trialEndsAt: done.trialEndsAt });
    }

    // ------------------------------------------------------------------
    // Sign-in of an existing subscriber
    // ------------------------------------------------------------------
    if (action === "login") {
      const phone = body.phone;
      if (typeof phone !== "string") {
        return json({ ok: false, code: "bad_request" }, 400);
      }
      const { data: ok, error } = await admin.rpc("login_verify", {
        p_phone: phone,
        p_code: code,
        p_ip: ip,
      });
      if (error) return json({ ok: false, code: "server_error" }, 500);
      if (!ok?.ok) return json(ok);

      const tokenHash = await issueToken(ok.email);
      if (!tokenHash) return json({ ok: false, code: "link_failed" }, 500);
      return json({ ok: true, tokenHash });
    }

    return json({ ok: false, code: "bad_request" }, 400);
  } catch (_e) {
    return json({ ok: false, code: "server_error" }, 500);
  }
});
