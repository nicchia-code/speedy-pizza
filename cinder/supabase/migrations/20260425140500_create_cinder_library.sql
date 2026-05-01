create table if not exists public.books (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  authors text[] not null default '{}',
  source_file_name text not null,
  format text not null,
  chapter_count integer not null check (chapter_count >= 0),
  word_count integer not null check (word_count >= 0),
  character_count integer not null check (character_count >= 0),
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.book_chapters (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  position integer not null check (position > 0),
  title text not null,
  content text not null,
  word_count integer not null check (word_count >= 0),
  character_count integer not null check (character_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (book_id, position)
);

create index if not exists books_owner_id_created_at_idx
  on public.books (owner_id, created_at desc);

create index if not exists book_chapters_book_id_position_idx
  on public.book_chapters (book_id, position);

create index if not exists book_chapters_owner_id_idx
  on public.book_chapters (owner_id);

create or replace function public.cinder_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_books_updated_at on public.books;
create trigger set_books_updated_at
before update on public.books
for each row
execute function public.cinder_set_updated_at();

drop trigger if exists set_book_chapters_updated_at on public.book_chapters;
create trigger set_book_chapters_updated_at
before update on public.book_chapters
for each row
execute function public.cinder_set_updated_at();

alter table public.books enable row level security;
alter table public.book_chapters enable row level security;

drop policy if exists "Users can read their books" on public.books;
create policy "Users can read their books"
on public.books
for select
to authenticated
using (owner_id = auth.uid());

drop policy if exists "Users can insert their books" on public.books;
create policy "Users can insert their books"
on public.books
for insert
to authenticated
with check (owner_id = auth.uid());

drop policy if exists "Users can update their books" on public.books;
create policy "Users can update their books"
on public.books
for update
to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

drop policy if exists "Users can delete their books" on public.books;
create policy "Users can delete their books"
on public.books
for delete
to authenticated
using (owner_id = auth.uid());

drop policy if exists "Users can read their chapters" on public.book_chapters;
create policy "Users can read their chapters"
on public.book_chapters
for select
to authenticated
using (owner_id = auth.uid());

drop policy if exists "Users can insert chapters for their books" on public.book_chapters;
create policy "Users can insert chapters for their books"
on public.book_chapters
for insert
to authenticated
with check (
  owner_id = auth.uid()
  and exists (
    select 1
    from public.books
    where books.id = book_chapters.book_id
      and books.owner_id = auth.uid()
  )
);

drop policy if exists "Users can update their chapters" on public.book_chapters;
create policy "Users can update their chapters"
on public.book_chapters
for update
to authenticated
using (owner_id = auth.uid())
with check (
  owner_id = auth.uid()
  and exists (
    select 1
    from public.books
    where books.id = book_chapters.book_id
      and books.owner_id = auth.uid()
  )
);

drop policy if exists "Users can delete their chapters" on public.book_chapters;
create policy "Users can delete their chapters"
on public.book_chapters
for delete
to authenticated
using (owner_id = auth.uid());

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.books to authenticated;
grant select, insert, update, delete on public.book_chapters to authenticated;
