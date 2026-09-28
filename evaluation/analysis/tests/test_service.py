import csv
import io
import shutil
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from starlette.testclient import TestClient

from network_defense_analysis import AnalysisError, service
from network_defense_analysis.archive import write_result_zip
from network_defense_analysis.report import OUTPUT_HEADERS
from test_analysis import AnalysisTest


ROUTES = (
    ("/v1/analyze", "analyze", "analyze-result.zip", "analysis"),
    ("/v1/study/analyze", "analyze_study", "study-analysis.zip", "study"),
    ("/v1/study/pilot", "pilot_study", "study-pilot.zip", "study"),
)


def archive_bytes():
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w"):
        pass
    return stream.getvalue()


class ServiceTest(unittest.TestCase):
    def setUp(self):
        self.app = service.create_app()
        self.client = TestClient(self.app)

    @staticmethod
    def successful_runner(name):
        if name == "analyze":
            return lambda source, output: (output / "result.txt").write_text("analyze")

        def write_study_result(source, output):
            with zipfile.ZipFile(output, "w") as result:
                result.writestr("result.txt", "study")

        return write_study_result

    def test_health_and_archive_routes(self):
        self.assertEqual(self.client.get("/healthz").status_code, 200)
        for path, runner, filename, _ in ROUTES:
            with self.subTest(path=path), patch.object(
                service, runner, side_effect=self.successful_runner(runner)
            ):
                response = self.client.post(
                    path,
                    content=archive_bytes(),
                    headers={"content-type": "application/zip"},
                )
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.headers["content-type"], "application/zip")
            self.assertIn(filename, response.headers["content-disposition"])
            with zipfile.ZipFile(io.BytesIO(response.content)) as result:
                self.assertIn("result.txt", result.namelist())

    def test_archive_route_rejections(self):
        for path, _, _, contract in ROUTES:
            with self.subTest(path=path, reason="content type"):
                response = self.client.post(
                    path,
                    content=b"x",
                    headers={"content-type": "text/plain"},
                )
                self.assertEqual(response.status_code, 415)

            with self.subTest(path=path, reason="invalid content length"):
                response = self.client.post(
                    path,
                    content=b"x",
                    headers={"content-type": "application/zip", "content-length": "-1"},
                )
                self.assertEqual(response.status_code, 422)

            with self.subTest(path=path, reason="excessive content length"):
                response = self.client.post(
                    path,
                    content=b"x",
                    headers={
                        "content-type": "application/zip",
                        "content-length": str(service.MAX_REQUEST_BYTES + 1),
                    },
                )
                self.assertEqual(response.status_code, 413)

            with self.subTest(path=path, reason="invalid archive"):
                runner = next(route[1] for route in ROUTES if route[0] == path)
                with patch.object(service, runner, side_effect=AnalysisError("invalid archive")):
                    response = self.client.post(
                        path,
                        content=archive_bytes(),
                        headers={"content-type": "application/zip"},
                    )
                self.assertEqual(response.status_code, 422)
                self.assertEqual(
                    response.json()["detail"],
                    f"the ZIP does not satisfy the {contract} contract",
                )

    def test_archive_route_busy_and_slot_restoration(self):
        self.app.state.service.active = self.app.state.service.concurrency
        for path, _, _, _ in ROUTES:
            with self.subTest(path=path):
                response = self.client.post(
                    path,
                    content=archive_bytes(),
                    headers={"content-type": "application/zip"},
                )
                self.assertEqual(response.status_code, 429)
                self.assertEqual(
                    self.app.state.service.active,
                    self.app.state.service.concurrency,
                )

    def test_archive_route_streamed_request_overflow_restores_slot(self):
        body = archive_bytes()
        self.app.state.service.limit = len(body) - 1
        for path, runner, _, _ in ROUTES:
            with self.subTest(path=path), patch.object(
                service, runner, side_effect=self.successful_runner(runner)
            ):
                response = self.client.post(
                    path,
                    content=iter([body]),
                    headers={"content-type": "application/zip"},
                )
            self.assertEqual(response.status_code, 413)
            self.assertEqual(self.app.state.service.active, 0)

    def test_archive_route_response_overflow_restores_slot(self):
        self.app.state.service.response_limit = 1
        for path, runner, _, _ in ROUTES:
            with self.subTest(path=path), patch.object(
                service, runner, side_effect=self.successful_runner(runner)
            ):
                response = self.client.post(
                    path,
                    content=archive_bytes(),
                    headers={"content-type": "application/zip"},
                )
            self.assertEqual(response.status_code, 500)
            self.assertEqual(self.app.state.service.active, 0)

    def test_archive_route_internal_failure_restores_slot(self):
        for path, runner, _, _ in ROUTES:
            with self.subTest(path=path), patch.object(
                service, runner, side_effect=RuntimeError("secret traceback")
            ):
                response = self.client.post(
                    path,
                    content=archive_bytes(),
                    headers={"content-type": "application/zip"},
                )
            self.assertEqual(response.status_code, 500)
            self.assertNotIn("traceback", response.text.lower())
            self.assertTrue(response.headers["x-correlation-id"])
            self.assertEqual(self.app.state.service.active, 0)

    def test_archive_route_temporary_cleanup(self):
        created = []
        original_mkdtemp = tempfile.mkdtemp

        def tracked_mkdtemp(*args, **kwargs):
            path = original_mkdtemp(*args, **kwargs)
            created.append(Path(path))
            return path

        for path, runner, _, _ in ROUTES:
            with self.subTest(path=path):
                with (
                    patch.object(service.tempfile, "mkdtemp", side_effect=tracked_mkdtemp),
                    patch.object(service, runner, side_effect=self.successful_runner(runner)),
                ):
                    response = self.client.post(
                        path,
                        content=iter([archive_bytes()]),
                        headers={"content-type": "application/zip"},
                    )
                self.assertEqual(response.status_code, 200)

        self.assertTrue(created)
        self.assertTrue(all(not path.exists() for path in created))
        self.assertEqual(self.app.state.service.active, 0)
        for path in created:
            shutil.rmtree(path, ignore_errors=True)

    def test_result_writer_stream(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "result.txt").write_text("result")
            output = io.BytesIO()
            with patch("sys.stdout"):
                write_result_zip(root, output)
            with zipfile.ZipFile(io.BytesIO(output.getvalue())) as result:
                self.assertEqual(result.read("result.txt"), b"result")

    def test_analyze_round_trip_with_model_aware_zip(self):
        directory = AnalysisTest.make_fixture(cross_model=True)
        self.addCleanup(shutil.rmtree, directory, True)
        archive = directory.parent / "input.zip"
        with zipfile.ZipFile(archive, "w") as target:
            for path in directory.iterdir():
                target.write(path, path.name)
        self.addCleanup(Path.unlink, archive, missing_ok=True)
        response = self.client.post(
            "/v1/analyze",
            content=archive.read_bytes(),
            headers={"content-type": "application/zip"},
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["content-type"], "application/zip")
        with zipfile.ZipFile(io.BytesIO(response.content)) as result:
            self.assertSetEqual(
                set(result.namelist()),
                set(OUTPUT_HEADERS)
                | {
                    "analysis.json",
                    "metadata.json",
                    "figures/blast_radius_cdf.png",
                    "figures/plan_variation.png",
                },
            )
            self.assertNotIn("analyze-result.zip", result.namelist())
            rows = list(csv.DictReader(io.StringIO(result.read("primary_results.csv").decode())))
        self.assertEqual(
            [(row["model_variant"], row["baseline_model_variant"]) for row in rows],
            [("full", "full"), ("full_unconstrained", "full")],
        )


if __name__ == "__main__":
    unittest.main()
