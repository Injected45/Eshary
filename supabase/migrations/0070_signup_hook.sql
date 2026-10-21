-- 0070_signup_hook.sql
-- "Allow new users to sign up" has to stay ON: Supabase refuses anonymous
-- sign-ins (which every employee uses) when it is off. This hook closes the
-- door again for everything that is NOT an anonymous employee session: no one
-- can create an account by e-mail, phone or Google with the public app key.
-- Subscribers are created only by the Edge Function (admin API, which does not
-- run this hook) after a WhatsApp code.
--
-- It must never lock the employees out: any unexpected error lets the sign-in
-- through (the licence gate still keeps an empty account away from all data).
--
-- After running this file, switch it on in the dashboard:
--   Authentication > Auth Hooks > Before User Created > Postgres function
--   > schema public > function hook_before_user_created > Save.
-- Safe to run more than once.

begin;

create or replace function public.hook_before_user_created(event jsonb)
returns jsonb
language plpgsql
stable
as $$
begin
  -- an anonymous session says so twice (the flag and the provider); either is
  -- enough, so a change in one never locks the employees out
  if coalesce((event -> 'user' ->> 'is_anonymous')::boolean, false)
     or (event -> 'user' -> 'app_metadata' ->> 'provider') = 'anonymous' then
    return '{}'::jsonb;
  end if;
  return jsonb_build_object(
    'error', jsonb_build_object(
      'http_code', 403,
      'message', 'التسجيل مغلق. اطلب تجربة من التطبيق.'
    )
  );
exception when others then
  return '{}'::jsonb;
end;
$$;

grant usage on schema public to supabase_auth_admin;
grant execute on function public.hook_before_user_created(jsonb) to supabase_auth_admin;
revoke execute on function public.hook_before_user_created(jsonb) from authenticated, anon, public;

commit;
