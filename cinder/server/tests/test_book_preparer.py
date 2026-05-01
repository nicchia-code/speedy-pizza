from __future__ import annotations

from io import BytesIO
import unittest
from zipfile import ZipFile

from server.book_preparer import (
    BookPreparationError,
    UnsupportedFormatError,
    prepare_book,
)


class BookPreparerTest(unittest.TestCase):
    def test_prepares_plain_text(self) -> None:
        prepared = prepare_book("sample.txt", b"Uno\n\nDue")

        self.assertEqual(prepared.format_label, "TXT")
        self.assertEqual(prepared.title, "sample")
        self.assertEqual(prepared.word_count, 2)
        self.assertEqual(prepared.sections[0].text, "Uno\n\nDue")

    def test_prepares_epub_spine_in_order_with_metadata(self) -> None:
        prepared = prepare_book("fallback.epub", _epub_bytes())

        self.assertEqual(prepared.format_label, "EPUB")
        self.assertEqual(prepared.title, "Libro Test")
        self.assertEqual(prepared.authors, ["Autrice Test"])
        self.assertEqual([section.title for section in prepared.sections], ["Uno", "Due"])
        self.assertIn("Prima frase.", prepared.sections[0].text)
        self.assertIn("Seconda frase.", prepared.sections[1].text)
        self.assertLess(
            prepared.text_preview.index("Prima frase."),
            prepared.text_preview.index("Seconda frase."),
        )

    def test_prepares_pb_concepts(self) -> None:
        prepared = prepare_book(
            "concepts.pb",
            b"""
;;;PB-METADATA-BEGIN;;;
{
  "metadata_version": 2,
  "title": "Libro a concetti",
  "authors": ["Autrice"],
  "spoiler_free_summary": "Una descrizione breve.",
  "chapter_count": 1,
  "concept_count": 2
}
;;;PB-METADATA-END;;;

===== CHAPTER 001: Le nozze =====

----- CONCEPT 001.001: Ingresso -----
Prima parte del testo reale.

----- CONCEPT 001.002: Decisione -----
Seconda parte del testo reale.
""",
        )

        self.assertEqual(prepared.format_label, "PB")
        self.assertEqual(prepared.title, "Libro a concetti")
        self.assertEqual(prepared.section_singular_label, "Frammento")
        self.assertEqual(
            [section.title for section in prepared.sections],
            ["Le nozze - Ingresso", "Le nozze - Decisione"],
        )

    def test_rejects_legacy_pb_without_metadata(self) -> None:
        with self.assertRaises(BookPreparationError):
            prepare_book("legacy.pb", b"===== CAPITOLO 1 =====\nPrima parte.")

    def test_rejects_unsupported_formats(self) -> None:
        with self.assertRaises(UnsupportedFormatError):
            prepare_book("book.pdf", b"%PDF")


def _epub_bytes() -> bytes:
    output = BytesIO()
    with ZipFile(output, "w") as archive:
        archive.writestr(
            "META-INF/container.xml",
            """<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
""",
        )
        archive.writestr(
            "OPS/content.opf",
            """<?xml version="1.0" encoding="utf-8"?>
<package version="3.0" xmlns="http://www.idpf.org/2007/opf"
         xmlns:dc="http://purl.org/dc/elements/1.1/">
  <metadata>
    <dc:title>Libro Test</dc:title>
    <dc:creator>Autrice Test</dc:creator>
  </metadata>
  <manifest>
    <item id="chapter-1" href="chapter1.xhtml" media-type="application/xhtml+xml" />
    <item id="chapter-2" href="chapter2.xhtml" media-type="application/xhtml+xml" />
  </manifest>
  <spine>
    <itemref idref="chapter-1" />
    <itemref idref="chapter-2" />
  </spine>
</package>
""",
        )
        archive.writestr(
            "OPS/chapter1.xhtml",
            "<html><body><h1>Uno</h1><p>Prima frase.</p></body></html>",
        )
        archive.writestr(
            "OPS/chapter2.xhtml",
            "<html><body><h1>Due</h1><p>Seconda frase.</p></body></html>",
        )
    return output.getvalue()


if __name__ == "__main__":
    unittest.main()
