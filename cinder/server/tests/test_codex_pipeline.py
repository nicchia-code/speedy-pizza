from __future__ import annotations

from hashlib import sha256
import unittest
from unittest.mock import patch

from server.codex_pipeline import (
    _parse_prepare_book_progress_line,
    prepare_epub_with_codex,
)


class CodexPipelineTest(unittest.TestCase):
    def test_prepares_epub_through_prepare_book_output(self) -> None:
        events: list[tuple[int, str]] = []

        def fake_run_prepare_book(*, input_path, output_dir, progress=None):
            self.assertEqual(input_path.name, "uploaded.epub")
            self.assertEqual(input_path.read_bytes(), b"fake epub")
            output_dir.mkdir(parents=True, exist_ok=True)
            pb_path = output_dir / "Libro_Test.pb"
            pb_path.write_text(_pb_source(), encoding="utf-8")
            if progress:
                progress(42, "Piano capitoli pronto")
            return {
                "all_in_one_output": str(pb_path),
                "used_fallback": False,
                "chapter_plan_used_fallback": False,
                "concept_fallback_count": 0,
                "count": 1,
            }

        with patch(
            "server.codex_pipeline._run_prepare_book",
            side_effect=fake_run_prepare_book,
        ):
            prepared = prepare_epub_with_codex(
                "uploaded.epub",
                b"fake epub",
                progress=lambda percent, label: events.append((percent, label)),
            )

        self.assertEqual(prepared.file_name, "uploaded.epub")
        self.assertEqual(prepared.id, sha256(b"fake epub").hexdigest())
        self.assertEqual(prepared.title, "Libro Test")
        self.assertEqual(prepared.authors, ["Autrice Test"])
        self.assertEqual(prepared.section_singular_label, "Frammento")
        self.assertEqual(prepared.metadata["source_file"], "uploaded.epub")
        self.assertEqual(prepared.metadata["preparation_engine"], "prepare-book")
        self.assertEqual(prepared.metadata["prepare_book"]["chapter_count"], 1)
        self.assertIn((42, "Piano capitoli pronto"), events)
        self.assertEqual(events[-1], (100, "Preparazione completata"))

    def test_parses_prepare_book_progress_lines(self) -> None:
        parsed = _parse_prepare_book_progress_line(
            "[####------------------------] 1/4  25% Piano capitoli"
        )

        self.assertEqual(parsed, (25, "Piano capitoli"))
        self.assertIsNone(_parse_prepare_book_progress_line("plain stderr"))


def _pb_source() -> str:
    return """
;;;PB-METADATA-BEGIN;;;
{
  "metadata_version": 2,
  "title": "Libro Test",
  "authors": ["Autrice Test"],
  "spoiler_free_summary": "Una descrizione breve.",
  "chapter_count": 1,
  "concept_count": 1,
  "chapters": [
    {
      "index": 1,
      "title": "Inizio",
      "kind": "chapter",
      "start_spine_index": 1,
      "end_spine_index": 1,
      "word_count": 4,
      "omitted_sentence_count": 0,
      "omitted_word_count": 0,
      "concept_count": 1,
      "concepts": [
        {
          "index": 1,
          "global_index": 1,
          "title": "Apertura",
          "start_sentence_index": 1,
          "end_sentence_index": 1,
          "word_count": 4
        }
      ]
    }
  ]
}
;;;PB-METADATA-END;;;

===== CHAPTER 001: Inizio =====

----- CONCEPT 001.001: Apertura -----

Prima parte del testo.
"""


if __name__ == "__main__":
    unittest.main()
