import io
import shutil
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from starlette.testclient import TestClient

from network_defense_analysis import service
from network_defense_analysis.archive import write_result_zip


def archive_bytes():
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w"):
        pass
    return stream.getvalue()


class ServiceTest(unittest.TestCase):
    def setUp(self):
        self.app = service.create_app()
        self.client = TestClient(self.app)

    def test_health_and_modes(self):
        self.assertEqual(self.client.get("/healthz").status_code, 200)
        with patch.object(service, "analyze", side_effect=lambda source, output, mode: (output / f"{mode}.txt").write_text(mode)):
            for mode in ("analyze", "pilot"):
                response = self.client.post(f"/v1/{mode}", content=archive_bytes(), headers={"content-type": "application/zip"})
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.headers["content-type"], "application/zip")
                with zipfile.ZipFile(io.BytesIO(response.content)) as result:
                    self.assertIn(f"{mode}.txt", result.namelist())

    def test_rejections_and_generic_failure(self):
        self.assertEqual(self.client.post("/v1/analyze", content=b"x", headers={"content-type": "text/plain"}).status_code, 415)
        self.assertEqual(self.client.post("/v1/analyze", content=b"x", headers={"content-type": "application/zip", "content-length": str(service.MAX_REQUEST_BYTES + 1)}).status_code, 413)
        self.assertEqual(self.client.post("/v1/analyze", content=b"x", headers={"content-type": "application/zip"}).status_code, 422)
        with patch.object(service, "analyze", side_effect=RuntimeError("secret traceback")):
            response = self.client.post("/v1/analyze", content=archive_bytes(), headers={"content-type": "application/zip"})
        self.assertEqual(response.status_code, 500)
        self.assertNotIn("traceback", response.text.lower())
        self.assertTrue(response.headers["x-correlation-id"])

        response = self.client.post(
            "/v1/analyze",
            content=archive_bytes(),
            headers={"content-type": "application/zip", "x-correlation-id": "x" * 129},
        )
        self.assertNotEqual(response.headers["x-correlation-id"], "x" * 129)

    def test_slot_rejection_and_result_writer_stream(self):
        self.app.state.service.active = 1
        self.assertEqual(self.client.post("/v1/analyze", content=archive_bytes(), headers={"content-type": "application/zip"}).status_code, 429)
        self.assertEqual(self.client.post("/v1/analyze", content=b"x", headers={"content-type": "text/plain"}).status_code, 415)
        self.assertEqual(self.app.state.service.active, 1)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "result.txt").write_text("result")
            output = io.BytesIO()
            with patch("sys.stdout"):
                write_result_zip(root, output)
            with zipfile.ZipFile(io.BytesIO(output.getvalue())) as result:
                self.assertEqual(result.read("result.txt"), b"result")

    def test_chunked_request_and_temporary_cleanup(self):
        created = []
        original_mkdtemp = tempfile.mkdtemp

        def tracked_mkdtemp(*args, **kwargs):
            path = original_mkdtemp(*args, **kwargs)
            created.append(Path(path))
            return path

        with (
            patch.object(service.tempfile, "mkdtemp", side_effect=tracked_mkdtemp),
            patch.object(service, "analyze", side_effect=lambda source, output, mode: (output / "result.txt").write_text(mode)),
        ):
            response = self.client.post(
                "/v1/analyze",
                content=iter([archive_bytes()]),
                headers={"content-type": "application/zip"},
            )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(created)
        self.assertTrue(all(not path.exists() for path in created))
        for path in created:
            shutil.rmtree(path, ignore_errors=True)

    def test_result_limit(self):
        self.app.state.service.response_limit = 1
        with patch.object(service, "analyze", side_effect=lambda source, output, mode: (output / "result.txt").write_text(mode)):
            response = self.client.post(
                "/v1/analyze",
                content=archive_bytes(),
                headers={"content-type": "application/zip"},
            )
        self.assertEqual(response.status_code, 500)
        self.assertEqual(self.app.state.service.active, 0)


if __name__ == "__main__":
    unittest.main()
