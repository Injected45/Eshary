-- 0069_party_reference_prefix.sql
-- Some senders always use the same letters in front of their reference number
-- (e.g. TRC185, TRC250, TRC300). The party keeps those letters, and the entry
-- form shows them fixed so only the changing number is typed.
-- Safe to run more than once.

begin;

alter table clients
  add column if not exists ref_prefix text;

alter table clients drop constraint if exists clients_ref_prefix_len;
alter table clients add constraint clients_ref_prefix_len
  check (ref_prefix is null or char_length(ref_prefix) between 1 and 20);

commit;
