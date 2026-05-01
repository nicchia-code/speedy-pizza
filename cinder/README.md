# Cinder

Cinder companion app for the Rabbit reader.

## Flutter

Run the web app with the Supabase defines in `.env`:

```bash
flutter run -d web-server --dart-define-from-file=.env
```

## EPUB Upload

The companion app now imports EPUB files directly in Flutter with `epubx`,
splits readable chapters in the client, then writes the book and chapter rows to
Supabase. The local Python server is not required for this path.

Apply the database migration in:

```bash
supabase/migrations/20260425140500_create_cinder_library.sql
```

Default table names are `books` and `book_chapters`. You can override them with:

```bash
--dart-define=CINDER_SUPABASE_BOOKS_TABLE=books
--dart-define=CINDER_SUPABASE_BOOK_CHAPTERS_TABLE=book_chapters
```

Minimum Supabase schema expected by the app:

```sql
create table public.books (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  authors text[] not null default '{}',
  source_file_name text not null,
  format text not null,
  chapter_count integer not null,
  word_count integer not null,
  character_count integer not null,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create table public.book_chapters (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  position integer not null,
  title text not null,
  content text not null,
  word_count integer not null,
  character_count integer not null,
  created_at timestamptz not null default now(),
  unique (book_id, position)
);
```

## Library Server

The local FastAPI server lives in `server/` and exposes `POST /prepare-books`
for EPUB, FB2, HTML, Markdown, PB and TXT uploads. EPUB uploads are converted
through the sibling `prepare-book` Codex pipeline when available. Uploads are
asynchronous: poll `GET /status/{job_id}` for percent and result.

```bash
python -m venv .venv-server
. .venv-server/bin/activate
python -m pip install -r server/requirements.txt
python -m uvicorn server.main:app --reload --host 127.0.0.1 --port 8787
```
