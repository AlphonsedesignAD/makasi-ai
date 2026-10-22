-- À exécuter dans Supabase > SQL Editor
create table conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade default auth.uid(),
  title text not null default 'Nouvelle discussion',
  created_at timestamptz default now()
);
create table messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations on delete cascade,
  user_id uuid not null references auth.users on delete cascade default auth.uid(),
  role text not null check (role in ('user','assistant')),
  content text not null,
  created_at timestamptz default now()
);
create table files (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade default auth.uid(),
  name text not null, path text not null, mime text, size bigint,
  folder text default 'Général',
  created_at timestamptz default now()
);
create index on messages (conversation_id, created_at);

alter table conversations enable row level security;
alter table messages enable row level security;
alter table files enable row level security;
create policy "own conv" on conversations for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own msg" on messages for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own files" on files for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Stockage privé : chaque utilisateur ne voit que son dossier
insert into storage.buckets (id, name, public) values ('files', 'files', false) on conflict do nothing;
create policy "own storage" on storage.objects for all
  using (bucket_id = 'files' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'files' and (storage.foldername(name))[1] = auth.uid()::text);
