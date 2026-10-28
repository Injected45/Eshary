-- 0079_app_releases.sql
-- Updating the installed app by itself (the direct APK).
--
-- Each new build is PUBLISHED as one row here (build number, version name,
-- notes, and one APK file per processor type: its public address and its
-- SHA-256). The app asks for the latest release when it opens and when it comes
-- back to the foreground; if its own build is older than a release marked
-- "mandatory", it shows a blocking "تحديث إلزامي" screen that downloads the
-- file, checks the SHA-256 and hands it to Android's installer. Nobody has to
-- be sent an APK again after the first build that contains this feature.
--
--   build_number  the Android versionCode base; strictly increasing
--   mandatory     true: every older build is blocked until it is updated
--   is_active     false: the release is withdrawn (a bad build) and the app
--                 behaves as if it was never published
--
-- The files are kept in the public Storage bucket "app-releases". Only the
-- service key (the publishing script) writes here; the app only READS the
-- latest release through latest_app_release(), which anyone may call (the
-- check also runs before sign-in).
-- Safe to run more than once.

begin;

create table if not exists app_releases (
  id            uuid primary key default gen_random_uuid(),
  platform      text not null default 'android' check (platform in ('android')),
  build_number  integer not null check (build_number > 0),
  version_name  text not null check (char_length(btrim(version_name)) between 1 and 40),
  mandatory     boolean not null default true,
  notes         text check (char_length(notes) <= 1000),
  -- {"arm64-v8a": {"url": "...", "sha256": "<64 hex>", "size": 16328683},
  --  "armeabi-v7a": {...}}
  files         jsonb not null check (
                  jsonb_typeof(files) = 'object'
                  and (files ? 'arm64-v8a' or files ? 'armeabi-v7a')),
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  unique (platform, build_number)
);
alter table app_releases enable row level security;
revoke all on app_releases from anon, authenticated;

-- The release the app should look at.
--   build_number / version_name / notes / files : the newest ACTIVE release
--   min_build_number : the newest ACTIVE mandatory release. An app older than
--                      this MUST update, even when the newest release itself is
--                      optional (a later optional release never un-forces it).
create or replace function latest_app_release(p_platform text default 'android')
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  r      app_releases;
  v_min  integer;
begin
  select * into r
    from app_releases a
   where a.platform = coalesce(p_platform, 'android') and a.is_active
   order by a.build_number desc
   limit 1;
  if not found then
    return null;
  end if;
  select coalesce(max(a.build_number), 0) into v_min
    from app_releases a
   where a.platform = r.platform and a.is_active and a.mandatory;
  return jsonb_build_object(
    'buildNumber',    r.build_number,
    'versionName',    r.version_name,
    'notes',          r.notes,
    'files',          r.files,
    'mandatory',      r.mandatory,
    'minBuildNumber', v_min,
    'publishedAt',    r.created_at);
end;
$$;
revoke all on function latest_app_release(text) from public;
grant execute on function latest_app_release(text) to anon, authenticated;

-- The public bucket the APK files are uploaded to (the publishing script).
-- Skipped where Storage does not exist (a plain Postgres).
do $$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit)
    values ('app-releases', 'app-releases', true, 104857600)
    on conflict (id) do update set public = true;
  end if;
end $$;

-- =========================================================================
-- The platform (ESHARI Admin): see the releases, withdraw or restore one
-- =========================================================================
create or replace function platform_releases_list()
returns table (
  id uuid, build_number integer, version_name text, mandatory boolean,
  is_active boolean, notes text, created_at timestamptz, files jsonb
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  perform _platform_need('super_admin', 'admin', 'support', 'viewer');
  return query
  select a.id, a.build_number, a.version_name, a.mandatory, a.is_active,
         a.notes, a.created_at, a.files
    from app_releases a
   order by a.build_number desc
   limit 50;
end;
$$;
revoke all on function platform_releases_list() from public, anon;
grant execute on function platform_releases_list() to authenticated;

-- Withdraws a release (is_active = false: the app ignores it at once) or
-- restores it. The newest active release is what the app offers.
create or replace function platform_release_set_active(p_id uuid, p_active boolean)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r app_releases;
begin
  perform _platform_need('super_admin', 'admin');
  select * into r from app_releases where id = p_id for update;
  if not found then
    raise exception 'release_not_found' using errcode = 'P0001';
  end if;
  update app_releases set is_active = coalesce(p_active, true) where id = p_id;
  perform _audit('app_release_toggled', 'app_release', p_id::text,
                 jsonb_build_object('active', r.is_active),
                 jsonb_build_object('active', coalesce(p_active, true),
                                    'build', r.build_number));
end;
$$;
revoke all on function platform_release_set_active(uuid, boolean) from public, anon;
grant execute on function platform_release_set_active(uuid, boolean) to authenticated;

commit;
