from __future__ import annotations

from dataclasses import asdict, dataclass
from hashlib import sha256
from html import unescape
from html.parser import HTMLParser
from io import BytesIO
import json
import posixpath
import re
from typing import Any
from urllib.parse import unquote, urlsplit
from xml.etree import ElementTree
from zipfile import BadZipFile, ZipFile


SUPPORTED_EXTENSIONS = {
    "epub",
    "fb2",
    "htm",
    "html",
    "markdown",
    "md",
    "pb",
    "txt",
}

_PB_METADATA_BEGIN = ";;;PB-METADATA-BEGIN;;;"
_PB_METADATA_END = ";;;PB-METADATA-END;;;"
_WORD_RE = re.compile(r"\b[\w']+\b", re.UNICODE)


class BookPreparationError(ValueError):
    """Raised when a known format cannot be prepared."""


class UnsupportedFormatError(BookPreparationError):
    """Raised when the uploaded file extension is not supported."""


@dataclass(frozen=True)
class PreparedSection:
    index: int
    title: str
    text: str
    word_count: int
    character_count: int

    @classmethod
    def from_text(cls, index: int, title: str, text: str) -> "PreparedSection":
        normalized_text = _normalize_text(text)
        return cls(
            index=index,
            title=_clean_text(title) or f"Sezione {index}",
            text=normalized_text,
            word_count=_word_count(normalized_text),
            character_count=len(normalized_text),
        )


@dataclass(frozen=True)
class PreparedBook:
    id: str
    file_name: str
    format_label: str
    title: str
    authors: list[str]
    byte_size: int
    word_count: int
    character_count: int
    text_preview: str
    sections: list[PreparedSection]
    metadata: dict[str, Any]
    section_singular_label: str = "Capitolo"
    section_plural_label: str = "Capitoli"
    spoiler_free_summary: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def prepare_book(file_name: str, data: bytes) -> PreparedBook:
    extension = _extension(file_name)
    if extension not in SUPPORTED_EXTENSIONS:
        raise UnsupportedFormatError(
            f"Formato non supportato: {'.' + extension if extension else file_name}"
        )

    title = _title_from_file_name(file_name)
    authors: list[str] = []
    metadata: dict[str, Any] = {}
    section_singular_label = "Capitolo"
    section_plural_label = "Capitoli"
    spoiler_free_summary: str | None = None

    if extension in {"txt", "md", "markdown"}:
        text = _decode_text_bytes(data)
        format_label = "TXT" if extension == "txt" else "Markdown"
        sections = [PreparedSection.from_text(1, "Testo", text)]
    elif extension in {"html", "htm"}:
        text, heading = _extract_markup_text(_decode_text_bytes(data))
        format_label = "HTML"
        sections = [PreparedSection.from_text(1, heading or "Testo", text)]
    elif extension == "fb2":
        text = _extract_fb2_text(_decode_text_bytes(data))
        format_label = "FB2"
        sections = [PreparedSection.from_text(1, "Testo", text)]
    elif extension == "epub":
        epub = _extract_epub(data)
        format_label = "EPUB"
        title = epub.title or title
        authors = epub.authors
        metadata = epub.metadata
        sections = epub.sections
    elif extension == "pb":
        pb = _extract_pb(data)
        format_label = "PB"
        title = pb.title
        authors = pb.authors
        metadata = pb.metadata
        sections = pb.sections
        section_singular_label = pb.section_singular_label
        section_plural_label = pb.section_plural_label
        spoiler_free_summary = pb.spoiler_free_summary
    else:
        raise UnsupportedFormatError(f"Formato non supportato: .{extension}")

    sections = [section for section in sections if section.text]
    if not sections:
        raise BookPreparationError("Il file non contiene testo leggibile.")

    joined_text = _normalize_text("\n\n".join(section.text for section in sections))
    digest = sha256(data).hexdigest()

    return PreparedBook(
        id=digest,
        file_name=file_name,
        format_label=format_label,
        title=title,
        authors=authors,
        byte_size=len(data),
        word_count=_word_count(joined_text),
        character_count=len(joined_text),
        text_preview=_preview(joined_text),
        sections=sections,
        metadata=metadata,
        section_singular_label=section_singular_label,
        section_plural_label=section_plural_label,
        spoiler_free_summary=spoiler_free_summary,
    )


@dataclass(frozen=True)
class _ExtractedEpub:
    title: str | None
    authors: list[str]
    metadata: dict[str, Any]
    sections: list[PreparedSection]


@dataclass(frozen=True)
class _ExtractedPb:
    title: str
    authors: list[str]
    spoiler_free_summary: str | None
    metadata: dict[str, Any]
    sections: list[PreparedSection]
    section_singular_label: str
    section_plural_label: str


class _MarkupTextExtractor(HTMLParser):
    _block_tags = {
        "address",
        "article",
        "aside",
        "blockquote",
        "br",
        "dd",
        "div",
        "dl",
        "dt",
        "figcaption",
        "figure",
        "footer",
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6",
        "header",
        "hr",
        "li",
        "main",
        "nav",
        "ol",
        "p",
        "pre",
        "section",
        "table",
        "tbody",
        "td",
        "tfoot",
        "th",
        "thead",
        "tr",
        "ul",
    }
    _ignored_tags = {"head", "script", "style", "title"}
    _heading_tags = {"h1", "h2", "h3"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._parts: list[str] = []
        self._ignored_depth = 0
        self._heading_depth = 0
        self._heading_parts: list[str] = []
        self.heading: str | None = None

    def handle_starttag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        normalized_tag = tag.lower()
        if normalized_tag in self._ignored_tags:
            self._ignored_depth += 1
            return
        if self._ignored_depth:
            return
        if normalized_tag in self._block_tags:
            self._parts.append("\n")
        if normalized_tag in self._heading_tags and self.heading is None:
            self._heading_depth += 1
            self._heading_parts = []

    def handle_startendtag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        normalized_tag = tag.lower()
        if not self._ignored_depth and normalized_tag in self._block_tags:
            self._parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        normalized_tag = tag.lower()
        if normalized_tag in self._ignored_tags and self._ignored_depth:
            self._ignored_depth -= 1
            return
        if self._ignored_depth:
            return
        if normalized_tag in self._heading_tags and self._heading_depth:
            self._heading_depth -= 1
            if self.heading is None:
                heading = _normalize_text(" ".join(self._heading_parts))
                if heading:
                    self.heading = heading
            self._heading_parts = []
        if normalized_tag in self._block_tags:
            self._parts.append("\n")

    def handle_data(self, data: str) -> None:
        if self._ignored_depth:
            return
        self._parts.append(data)
        if self._heading_depth:
            self._heading_parts.append(data)

    @property
    def text(self) -> str:
        return _normalize_text("".join(self._parts))


def _extract_epub(data: bytes) -> _ExtractedEpub:
    try:
        archive = ZipFile(BytesIO(data))
    except BadZipFile as exc:
        raise BookPreparationError("EPUB non valido.") from exc

    with archive:
        files_by_path = _epub_files_by_path(archive)
        container_name = files_by_path.get("meta-inf/container.xml")
        if container_name is None:
            raise BookPreparationError("EPUB senza META-INF/container.xml.")

        container_root = _parse_xml_bytes(archive.read(container_name))
        root_file = _find_first_xml_element(container_root, "rootfile")
        package_path = root_file.attrib.get("full-path") if root_file is not None else None
        if not package_path:
            raise BookPreparationError("EPUB senza rootfile nel container.")

        package_key = _normalize_zip_path(package_path)
        package_name = files_by_path.get(package_key)
        if package_name is None:
            raise BookPreparationError(f"Package EPUB non trovato: {package_path}")

        package_dir = posixpath.dirname(package_key)
        package_root = _parse_xml_bytes(archive.read(package_name))
        metadata = _extract_epub_metadata(package_root)

        manifest: dict[str, str] = {}
        for item in _find_xml_elements(package_root, "item"):
            item_id = item.attrib.get("id")
            href = item.attrib.get("href")
            if item_id and href:
                manifest[item_id] = _resolve_zip_path(package_dir, href)

        spine_paths: list[str] = []
        for item_ref in _find_xml_elements(package_root, "itemref"):
            idref = item_ref.attrib.get("idref")
            if idref and idref in manifest:
                spine_paths.append(manifest[idref])

        sections = _extract_epub_sections_from_paths(
            archive=archive,
            files_by_path=files_by_path,
            paths=spine_paths,
        )

        if not sections:
            html_paths = sorted(
                path
                for path in files_by_path
                if path.endswith((".xhtml", ".xhtm", ".html", ".htm"))
            )
            sections = _extract_epub_sections_from_paths(
                archive=archive,
                files_by_path=files_by_path,
                paths=html_paths,
            )

        if not sections:
            raise BookPreparationError("EPUB senza contenuto testuale leggibile.")

        return _ExtractedEpub(
            title=_clean_text(metadata.get("title")),
            authors=_dedupe_clean_strings(metadata.get("authors", [])),
            metadata=metadata,
            sections=sections,
        )


def _extract_epub_sections_from_paths(
    *,
    archive: ZipFile,
    files_by_path: dict[str, str],
    paths: list[str],
) -> list[PreparedSection]:
    sections: list[PreparedSection] = []
    seen_paths: set[str] = set()
    for path in paths:
        normalized_path = _normalize_zip_path(path)
        if normalized_path in seen_paths:
            continue
        seen_paths.add(normalized_path)
        archive_name = files_by_path.get(normalized_path)
        if archive_name is None:
            continue
        text, heading = _extract_markup_text(_decode_text_bytes(archive.read(archive_name)))
        if not text:
            continue
        sections.append(
            PreparedSection.from_text(
                len(sections) + 1,
                heading or f"Capitolo {len(sections) + 1}",
                text,
            )
        )
    return sections


def _extract_epub_metadata(root: ElementTree.Element) -> dict[str, Any]:
    titles: list[str] = []
    authors: list[str] = []
    languages: list[str] = []
    identifiers: list[str] = []

    for element in root.iter():
        local_name = _xml_local_name(element.tag)
        text = _clean_text(element.text)
        if not text:
            continue
        if local_name == "title":
            titles.append(text)
        elif local_name == "creator":
            authors.append(text)
        elif local_name == "language":
            languages.append(text)
        elif local_name == "identifier":
            identifiers.append(text)

    metadata: dict[str, Any] = {}
    if titles:
        metadata["title"] = titles[0]
    if authors:
        metadata["authors"] = _dedupe_clean_strings(authors)
    if languages:
        metadata["languages"] = _dedupe_clean_strings(languages)
    if identifiers:
        metadata["identifiers"] = _dedupe_clean_strings(identifiers)
    return metadata


def _extract_pb(data: bytes) -> _ExtractedPb:
    source = _decode_text_bytes(data)
    metadata, content, has_metadata = _split_pb_metadata(source)

    title = _clean_text(metadata.get("title"))
    authors = _dedupe_clean_strings(metadata.get("authors", []))
    spoiler_free_summary = _clean_text(metadata.get("spoiler_free_summary"))
    if not has_metadata or not title or not authors or not spoiler_free_summary:
        raise BookPreparationError(
            "File .pb senza metadati aggiornati: mancano title, authors o "
            "spoiler_free_summary. Rigeneralo con prepare-book."
        )

    is_concept_based = _metadata_int(metadata.get("metadata_version")) >= 2
    raw_sections = (
        _extract_pb_concepts_from_text(content)
        if is_concept_based
        else _extract_pb_chapters_from_text(content)
    )
    if not raw_sections:
        raise BookPreparationError("File .pb senza capitoli leggibili.")

    sections = [
        PreparedSection.from_text(index, section_title, section_text)
        for index, (section_title, section_text) in enumerate(raw_sections, start=1)
    ]

    return _ExtractedPb(
        title=title,
        authors=authors,
        spoiler_free_summary=spoiler_free_summary,
        metadata=metadata,
        sections=sections,
        section_singular_label="Frammento" if is_concept_based else "Capitolo",
        section_plural_label="Frammenti" if is_concept_based else "Capitoli",
    )


def _extract_fb2_text(source: str) -> str:
    try:
        root = ElementTree.fromstring(source)
    except ElementTree.ParseError as exc:
        raise BookPreparationError("FB2 non valido.") from exc

    bodies = [element for element in root.iter() if _xml_local_name(element.tag) == "body"]
    if not bodies:
        text, _heading = _extract_markup_text(source)
        return text

    parts: list[str] = []
    for body in bodies:
        _append_xml_text(body, parts)
        parts.append("\n\n")
    return _normalize_text("".join(parts))


def _split_pb_metadata(source: str) -> tuple[dict[str, Any], str, bool]:
    normalized_source = source.replace("\r\n", "\n").replace("\r", "\n")
    lines = normalized_source.split("\n")

    first_content_line = 0
    while first_content_line < len(lines) and not lines[first_content_line].strip():
        first_content_line += 1

    if (
        first_content_line >= len(lines)
        or lines[first_content_line].strip() != _PB_METADATA_BEGIN
    ):
        return {}, source, False

    metadata_lines: list[str] = []
    end_line = -1
    for index, line in enumerate(lines[first_content_line + 1 :], start=first_content_line + 1):
        if line.strip() == _PB_METADATA_END:
            end_line = index
            break
        metadata_lines.append(line)

    if end_line == -1:
        return {}, source, False

    metadata: dict[str, Any] = {}
    metadata_json = "\n".join(metadata_lines).strip()
    if metadata_json:
        try:
            decoded = json.loads(metadata_json)
        except json.JSONDecodeError:
            decoded = {}
        if isinstance(decoded, dict):
            metadata = {str(key): value for key, value in decoded.items()}

    content = "\n".join(lines[end_line + 1 :])
    return metadata, content, True


def _extract_pb_chapters_from_text(source: str) -> list[tuple[str, str]]:
    lines = source.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    marker_re = re.compile(r"^\s*={5,}\s*(.*?)\s*={5,}\s*$")
    chapters: list[tuple[str, str]] = []
    section_buffer: list[str] = []
    chapter_title = "Capitolo 1"
    fallback_index = 2
    found_marker = False

    def flush_section() -> None:
        nonlocal section_buffer
        section_text = _normalize_text("\n".join(section_buffer))
        if section_text:
            chapters.append((chapter_title, section_text))
        section_buffer = []

    for line in lines:
        marker_match = marker_re.match(line.strip())
        if marker_match is None:
            section_buffer.append(line)
            continue

        flush_section()
        marker_text = _clean_text(marker_match.group(1))
        if marker_text:
            chapter_title = marker_text
        else:
            chapter_title = f"Capitolo {fallback_index}"
            fallback_index += 1
        found_marker = True

    flush_section()

    if not chapters and not found_marker:
        fallback_text = _normalize_text(source)
        if fallback_text:
            return [("Capitolo 1", fallback_text)]

    return chapters


def _extract_pb_concepts_from_text(source: str) -> list[tuple[str, str]]:
    lines = source.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    chapter_marker_re = re.compile(r"^\s*={5,}\s*(.*?)\s*={5,}\s*$")
    concept_marker_re = re.compile(r"^\s*-{5,}\s*(.*?)\s*-{5,}\s*$")

    chapter_title = ""
    concept_title = ""
    fallback_concept_index = 1
    found_concept_marker = False
    is_inside_concept = False
    section_buffer: list[str] = []
    concepts: list[tuple[str, str]] = []

    def flush_concept() -> None:
        nonlocal section_buffer
        if not is_inside_concept:
            section_buffer = []
            return
        text = _normalize_text("\n".join(section_buffer))
        if text:
            concepts.append((_combine_pb_concept_title(chapter_title, concept_title), text))
        section_buffer = []

    for line in lines:
        stripped_line = line.strip()
        chapter_match = chapter_marker_re.match(stripped_line)
        if chapter_match is not None:
            flush_concept()
            chapter_title = _clean_pb_structured_marker_title(chapter_match.group(1))
            concept_title = ""
            is_inside_concept = False
            continue

        concept_match = concept_marker_re.match(stripped_line)
        if concept_match is not None:
            flush_concept()
            concept_title = _clean_pb_structured_marker_title(concept_match.group(1))
            if not concept_title:
                concept_title = f"Frammento {fallback_concept_index}"
            fallback_concept_index += 1
            found_concept_marker = True
            is_inside_concept = True
            continue

        if is_inside_concept:
            section_buffer.append(line)

    flush_concept()

    if not concepts and not found_concept_marker:
        return _extract_pb_chapters_from_text(source)
    return concepts


def _clean_pb_structured_marker_title(raw_title: str | None) -> str:
    title = _clean_text(raw_title)
    if not title:
        return ""
    return re.sub(
        r"^(?:chapter|capitolo|concept|concetto)\s+[\d.]+\s*:\s*",
        "",
        title,
        flags=re.IGNORECASE,
    ).strip()


def _combine_pb_concept_title(chapter_title: str, concept_title: str) -> str:
    clean_chapter_title = chapter_title.strip()
    clean_concept_title = concept_title.strip()
    if not clean_chapter_title:
        return clean_concept_title or "Frammento"
    if (
        not clean_concept_title
        or clean_chapter_title.lower() == clean_concept_title.lower()
    ):
        return clean_chapter_title
    return f"{clean_chapter_title} - {clean_concept_title}"


def _extract_markup_text(source: str) -> tuple[str, str | None]:
    parser = _MarkupTextExtractor()
    parser.feed(source)
    parser.close()
    return parser.text, parser.heading


def _append_xml_text(element: ElementTree.Element, parts: list[str]) -> None:
    local_name = _xml_local_name(element.tag)
    if local_name in {"p", "section", "title", "subtitle", "empty-line"}:
        parts.append("\n")
    if element.text:
        parts.append(element.text)
    for child in element:
        _append_xml_text(child, parts)
        if child.tail:
            parts.append(child.tail)
    if local_name in {"p", "section", "title", "subtitle"}:
        parts.append("\n")


def _epub_files_by_path(archive: ZipFile) -> dict[str, str]:
    files_by_path: dict[str, str] = {}
    for name in archive.namelist():
        if name.endswith("/"):
            continue
        normalized_name = _normalize_zip_path(name)
        files_by_path[normalized_name] = name
        decoded_name = _normalize_zip_path(unquote(name))
        files_by_path[decoded_name] = name
    return files_by_path


def _parse_xml_bytes(data: bytes) -> ElementTree.Element:
    try:
        return ElementTree.fromstring(_decode_text_bytes(data))
    except ElementTree.ParseError as exc:
        raise BookPreparationError("XML non valido nel file libro.") from exc


def _find_first_xml_element(
    root: ElementTree.Element, local_name: str
) -> ElementTree.Element | None:
    for element in root.iter():
        if _xml_local_name(element.tag) == local_name.lower():
            return element
    return None


def _find_xml_elements(
    root: ElementTree.Element, local_name: str
) -> list[ElementTree.Element]:
    normalized_local_name = local_name.lower()
    return [
        element
        for element in root.iter()
        if _xml_local_name(element.tag) == normalized_local_name
    ]


def _xml_local_name(tag: str) -> str:
    if "}" in tag:
        return tag.rsplit("}", 1)[1].lower()
    return tag.lower()


def _resolve_zip_path(base_path: str, href: str) -> str:
    href_path = unquote(urlsplit(href).path)
    if not href_path:
        return _normalize_zip_path(base_path)
    if base_path:
        return _normalize_zip_path(posixpath.join(base_path, href_path))
    return _normalize_zip_path(href_path)


def _normalize_zip_path(path: str) -> str:
    normalized = path.replace("\\", "/")
    normalized = posixpath.normpath(normalized)
    if normalized == ".":
        return ""
    return normalized.lstrip("/").lower()


def _decode_text_bytes(data: bytes) -> str:
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("latin-1", errors="replace")


def _normalize_text(source: str) -> str:
    text = unescape(source)
    text = text.replace("\r\n", "\n").replace("\r", "\n").replace("\xa0", " ")
    text = re.sub(r"[ \t\f\v]+", " ", text)
    text = re.sub(r" *\n *", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def _clean_text(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    text = re.sub(r"\s+", " ", value.replace("\xa0", " ")).strip()
    return text or None


def _dedupe_clean_strings(value: Any) -> list[str]:
    if not isinstance(value, list):
        value = [value]
    result: list[str] = []
    seen: set[str] = set()
    for item in value:
        cleaned = _clean_text(item)
        if not cleaned:
            continue
        key = cleaned.casefold()
        if key in seen:
            continue
        result.append(cleaned)
        seen.add(key)
    return result


def _metadata_int(value: Any) -> int:
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value)
        except ValueError:
            return 0
    return 0


def _word_count(text: str) -> int:
    return len(_WORD_RE.findall(text))


def _preview(text: str, limit: int = 420) -> str:
    normalized = re.sub(r"\s+", " ", text).strip()
    if len(normalized) <= limit:
        return normalized
    return normalized[: limit - 1].rstrip() + "..."


def _extension(file_name: str) -> str:
    if "." not in file_name:
        return ""
    return file_name.rsplit(".", 1)[1].lower()


def _title_from_file_name(file_name: str) -> str:
    base_name = file_name.rsplit("/", 1)[-1].rsplit("\\", 1)[-1]
    if "." in base_name:
        base_name = base_name.rsplit(".", 1)[0]
    cleaned = re.sub(r"[_-]+", " ", base_name).strip()
    return cleaned or file_name
