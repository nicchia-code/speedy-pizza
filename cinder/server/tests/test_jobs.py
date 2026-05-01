from __future__ import annotations

import time
import unittest
from unittest.mock import patch

from server.book_preparer import prepare_book
from server.jobs import create_prepare_job, get_prepare_job


class PrepareJobsTest(unittest.TestCase):
    def test_runs_prepare_job_in_background(self) -> None:
        def fake_prepare(file_name, data, progress=None):
            if progress:
                progress(30, "Mock in corso")
                progress(80, "Mock quasi pronto")
            return prepare_book(file_name, data)

        with patch("server.jobs.prepare_uploaded_book", side_effect=fake_prepare):
            job = create_prepare_job("sample.txt", b"Uno due")
            completed = _wait_for_job(job.id)

        self.assertEqual(completed.status, "completed")
        self.assertEqual(completed.percent, 100)
        self.assertEqual(completed.book["title"], "sample")
        self.assertEqual(completed.book["word_count"], 2)
        self.assertGreaterEqual(len(completed.events), 2)


def _wait_for_job(job_id: str, timeout: float = 2.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        job = get_prepare_job(job_id)
        if job is not None and job.status in {"completed", "failed"}:
            return job
        time.sleep(0.01)
    raise AssertionError("job did not finish")


if __name__ == "__main__":
    unittest.main()
