# Cinder Library Server

Server FastAPI locale per preparare i libri caricati dalla companion app.

Gli EPUB passano dalla pipeline `prepare-book`, quindi usano `codex exec --json`
per generare `.pb` v2 con descrizione e frammenti concettuali. Gli altri
formati usano il parser deterministico locale.

## Setup

```bash
python -m venv .venv-server
. .venv-server/bin/activate
python -m pip install -r server/requirements.txt
```

Per eseguire i test:

```bash
python -m unittest discover server/tests
```

## Avvio

```bash
python -m uvicorn server.main:app --reload --host 127.0.0.1 --port 8787
```

Di default il server cerca `../prepare-book/.venv/bin/prepare-book`. Puoi
sovrascriverlo con:

```bash
export CINDER_PREPARE_BOOK_BIN=/path/to/prepare-book
```

## Endpoint

- `GET /health`
- `POST /prepare-books`: accoda uno o piu file e ritorna subito gli id dei job
- `GET /status`: lista job in memoria
- `GET /status/{job_id}`: stato, percentuale e risultato del job

Esempio:

```bash
curl -F "files=@/path/al/libro.epub" http://127.0.0.1:8787/prepare-books
curl http://127.0.0.1:8787/status/<job_id>
```

Formati iniziali: EPUB, FB2, HTML, Markdown, PB e TXT.
