-- ============================================================
--  MAKASI AI — Schéma Supabase (comptes + mémoire partagée)
--  À exécuter une seule fois dans : Supabase > SQL Editor
-- ============================================================
--
--  Ce schéma est volontairement simple :
--   * profiles : le nom affiché de chaque utilisateur
--   * chats    : une ligne par discussion, messages en JSON
--
--  Le site (localStorage -> cloud) et l'application Flutter
--  utilisent exactement les mêmes identifiants de discussions,
--  donc la mémoire est réellement partagée entre les deux.
-- ============================================================

-- ---------- 1. Profils ----------
create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  created_at   timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert
  with check (auth.uid() = id);

-- ---------- 2. Discussions (mémoire) ----------
create table if not exists public.chats (
  id         text primary key,
  user_id    uuid not null default auth.uid()
               references auth.users (id) on delete cascade,
  title      text not null default '',
  messages   jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists chats_user_updated_idx
  on public.chats (user_id, updated_at desc);

alter table public.chats enable row level security;

drop policy if exists "chats_select_own" on public.chats;
create policy "chats_select_own"
  on public.chats for select
  using (auth.uid() = user_id);

drop policy if exists "chats_insert_own" on public.chats;
create policy "chats_insert_own"
  on public.chats for insert
  with check (auth.uid() = user_id);

drop policy if exists "chats_update_own" on public.chats;
create policy "chats_update_own"
  on public.chats for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "chats_delete_own" on public.chats;
create policy "chats_delete_own"
  on public.chats for delete
  using (auth.uid() = user_id);

-- ---------- 3. Profil créé automatiquement à l'inscription ----------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'display_name', ''),
      split_part(coalesce(new.email, 'utilisateur'), '@', 1)
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- 4. Droits ----------
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.chats to authenticated;
grant select, insert, update on public.profiles to authenticated;

-- ============================================================
--  IMPORTANT (Supabase) :
--  Authentication > Providers > Email
--    -> désactivez « Confirm email » pour que la création de
--       compte connecte immédiatement l'utilisateur.
--       (Vous pouvez la réactiver plus tard, l'app gère aussi
--        le cas « vérifiez votre e-mail ».)
-- ============================================================
