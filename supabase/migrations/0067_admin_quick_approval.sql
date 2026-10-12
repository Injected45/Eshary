-- 0067_admin_quick_approval.sql
-- Simpler approval for the administrator:
--  * admin_pending_counts(): how many things wait for a decision (new trial
--    requests, phone changes proven by the new number, approvals whose WhatsApp
--    message failed), for the badge in Settings and the banner in the accounts
--    screen;
--  * the approval message tells the applicant exactly what to do next.
-- Safe to run more than once.

begin;

create or replace function admin_pending_counts()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_req integer;
  v_chg integer;
  v_fail integer;
begin
  perform _admin_only();
  select count(*)::int into v_req from trial_requests where status = 'pending_review';
  select count(*)::int into v_chg from phone_change_requests where status = 'pending_admin';
  select count(*)::int into v_fail
    from trial_requests r
   where r.status = 'approved'
     and r.approval_expires_at > _server_now()
     and (select c.send_status
            from wa_challenges c
           where c.request_id = r.id and c.purpose = 'activation'
           order by c.created_at desc limit 1) = 'failed';
  return jsonb_build_object(
    'requests', v_req,
    'phoneChanges', v_chg,
    'failedMessages', v_fail,
    'total', v_req + v_chg + v_fail
  );
end;
$$;
revoke all on function admin_pending_counts() from public, anon;
grant execute on function admin_pending_counts() to authenticated;

create or replace function admin_trial_decide(
  p_id       uuid,
  p_decision text,
  p_note     text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r      trial_requests;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_now  timestamptz := _server_now();
  v_hours integer;
  v_old  jsonb;
  v_send jsonb;
  v_intro text;
begin
  perform _admin_only();
  select * into r from trial_requests where id = p_id for update;
  if not found then
    raise exception 'request_not_found' using errcode = 'P0001';
  end if;
  if r.status in ('activated', 'rejected') and p_decision <> 'withdraw' then
    raise exception 'request_closed' using errcode = 'P0001';
  end if;
  v_old := jsonb_build_object('status', r.status, 'trial_hours', r.trial_hours,
                              'approved_at', r.approved_at);

  if p_decision in ('approve_72', 'approve_168', 'renew_approval') then
    if r.status = 'approved' and p_decision <> 'renew_approval' then
      raise exception 'already_approved' using errcode = 'P0001';
    end if;
    if r.status not in ('pending_review', 'needs_info', 'approved') then
      raise exception 'request_closed' using errcode = 'P0001';
    end if;
    v_hours := case p_decision when 'approve_72' then 72 when 'approve_168' then 168
                               else coalesce(r.trial_hours, 72) end;
    if exists (select 1 from trial_history h where h.phone = r.phone) then
      raise exception 'trial_used' using errcode = 'P0001';
    end if;
    update trial_requests
       set status = 'approved', approved_at = v_now, approved_by = auth.uid(),
           approval_expires_at = v_now + interval '7 days', trial_hours = v_hours,
           review_note = v_note, updated_at = v_now
     where id = r.id;
    perform _audit('trial_' || p_decision, 'trial_request', r.id::text, v_old,
                   jsonb_build_object('status', 'approved', 'trial_hours', v_hours,
                                      'approved_at', v_now,
                                      'approval_expires_at', v_now + interval '7 days'),
                   v_note);
    -- The code goes out with the approval. If the message fails the approval
    -- stays; the applicant (or an administrator) asks for another.
    v_intro := 'تمت الموافقة على طلب تجربتك في إشاري لمدة ' ||
               case v_hours when 72 then '3 أيام' else 'أسبوع' end || E'.\n' ||
               E'افتح التطبيق، اضغط «متابعة طلب التجربة»، وأدخل الرمز التالي لتبدأ تجربتك.\n';
    v_send := _issue_challenge('activation', r.id, null, r.phone, v_now, v_intro, _ip_hash(null));
    return jsonb_build_object('ok', true, 'status', 'approved', 'trialHours', v_hours,
                              'message', v_send);

  elsif p_decision = 'request_info' then
    if v_note is null then
      raise exception 'note_required' using errcode = 'P0001';
    end if;
    update trial_requests set status = 'needs_info', review_note = v_note, updated_at = v_now
     where id = r.id;
    -- a short notice so the applicant knows to open the app (no code in it)
    perform _wa_send(r.phone,
      'إشاري: طلب تجربتك يحتاج معلومات إضافية.' || E'\n' || '«' || v_note || '»' || E'\n' ||
      'افتح التطبيق ثم اضغط «متابعة طلب التجربة» لتراها وترد.');
  elsif p_decision = 'reject' then
    if v_note is null then
      raise exception 'note_required' using errcode = 'P0001';
    end if;
    update trial_requests set status = 'rejected', review_note = v_note, updated_at = v_now
     where id = r.id;
  elsif p_decision = 'withdraw' then
    if r.status <> 'approved' then
      raise exception 'not_approved' using errcode = 'P0001';
    end if;
    update trial_requests
       set status = 'pending_review', approved_at = null, approval_expires_at = null,
           review_note = v_note, updated_at = v_now
     where id = r.id;
  else
    raise exception 'invalid_decision' using errcode = 'P0001';
  end if;

  -- any code issued under the old state is dead
  update wa_challenges set revoked_at = now()
   where request_id = r.id and consumed_at is null and revoked_at is null;
  perform _audit('trial_' || p_decision, 'trial_request', r.id::text, v_old,
                 jsonb_build_object('status', (select status from trial_requests where id = r.id)),
                 v_note);
  return jsonb_build_object('ok', true,
                            'status', (select status from trial_requests where id = r.id));
end;
$$;
revoke all on function admin_trial_decide(uuid, text, text) from public, anon;
grant execute on function admin_trial_decide(uuid, text, text) to authenticated;

commit;
