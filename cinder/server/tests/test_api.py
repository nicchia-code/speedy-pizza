from __future__ import annotations

import asyncio
import unittest


try:
    from fastapi import HTTPException

    from server.main import health, prepare_books
except ModuleNotFoundError:
    HTTPException = None
    health = None
    prepare_books = None


class _FakeUploadFile:
    def __init__(self, file_name: str, data: bytes) -> None:
        self.filename = file_name
        self._data = data

    async def read(self) -> bytes:
        return self._data


@unittest.skipIf(prepare_books is None, "FastAPI dependencies are not installed")
class PrepareBooksApiTest(unittest.TestCase):
    def test_health_lists_supported_formats(self) -> None:
        assert health is not None

        payload = health()

        self.assertEqual(payload["status"], "ok")
        self.assertEqual(payload["mode"], "async")
        self.assertIn("epub", payload["supported_formats"])

    def test_requires_an_upload(self) -> None:
        assert HTTPException is not None
        assert prepare_books is not None

        with self.assertRaises(HTTPException) as context:
            asyncio.run(prepare_books())

        self.assertEqual(context.exception.status_code, 400)

    def test_prepares_uploaded_text_file(self) -> None:
        assert prepare_books is not None

        payload = asyncio.run(
            prepare_books(files=[_FakeUploadFile("sample.txt", b"Uno\n\nDue")])
        )

        self.assertEqual(payload["errors"], [])
        self.assertEqual(len(payload["jobs"]), 1)
        self.assertEqual(payload["jobs"][0]["file_name"], "sample.txt")
        self.assertIn("/status/", payload["jobs"][0]["status_url"])


if __name__ == "__main__":
    unittest.main()
