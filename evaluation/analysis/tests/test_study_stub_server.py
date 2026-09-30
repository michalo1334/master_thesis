"""Regression coverage for the test-only study HTTP double."""

import hashlib
import io
import json
import shutil
import tempfile
import threading
import unittest
import urllib.request
import zipfile
from http.server import ThreadingHTTPServer
from pathlib import Path

import test_analysis
from network_defense_analysis.study import analyze_study, pilot_study
from study_stub_server import Handler
from test_pilot import make_pilot_tier, pilot_configuration
from test_study import build_bundle


class StudyStubServerTest(unittest.TestCase):
    def setUp(self):
        self.paths = []

    def tearDown(self):
        for path in self.paths:
            shutil.rmtree(path, ignore_errors=True)

    def remember(self, path):
        self.paths.append(Path(path))
        return Path(path)

    def _bundle(self, mode, marker):
        tiers = []
        for label in ("tier-z", "tier-a", "tier-m"):
            tier = self.remember(
                make_pilot_tier(
                    label,
                    ["alt-a"],
                    [1],
                    plan_count=5,
                    attack_count=10,
                )
            )
            (tier / "graph.json").write_text(json.dumps({"fixture": marker}) + "\n")
            test_analysis.AnalysisTest.write_checksums(tier)
            tiers.append((label, tier))

        def mutate(spec):
            spec["pilot"] = pilot_configuration(
                plan_count_candidates=[5],
                attacks_per_plan_candidates=[10],
                subsamples=1,
            )

        bundle, directory = build_bundle(
            tiers,
            strategies=["alt-a"],
            budgets=[1],
            mutate_spec=mutate,
            mode=mode,
        )
        self.remember(bundle.parent)
        self.remember(directory)
        return bundle

    @staticmethod
    def _bundle_context(bundle):
        with zipfile.ZipFile(bundle) as archive:
            spec = json.loads(archive.read("study.json"))
        return [
            {
                "label": tier["label"],
                "archive": tier["archive"],
                "archive_sha256": tier["sha256"],
            }
            for tier in spec["tiers"]
        ]

    def _write_fixture(self, archives, mode, name, writer):
        source = self._bundle(mode, f"{mode}-source")
        requested = self._bundle(mode, f"{mode}-request")
        fixture = archives / name
        writer(source, fixture)
        expected = self._bundle_context(requested)
        with zipfile.ZipFile(fixture) as archive:
            metadata = json.loads(archive.read("study_metadata.json"))
        self.assertNotEqual(metadata["tier_context"], expected)
        return requested, expected

    @staticmethod
    def _post(port, route, bundle):
        request = urllib.request.Request(
            f"http://127.0.0.1:{port}{route}",
            data=bundle.read_bytes(),
            headers={"Content-Type": "application/zip"},
            method="POST",
        )
        with urllib.request.urlopen(request) as response:
            return response.read()

    def assert_echoed_archive(self, body, expected_context, *, final):
        with zipfile.ZipFile(io.BytesIO(body)) as archive:
            members = archive.infolist()
            files = {member.filename: archive.read(member) for member in members}

        names = [member.filename for member in members]
        self.assertEqual(names, sorted(names))
        self.assertTrue(all(member.date_time == (1980, 1, 1, 0, 0, 0) for member in members))

        metadata = json.loads(files["study_metadata.json"])
        self.assertEqual(metadata["tier_context"], expected_context)
        if final:
            self.assertEqual(json.loads(files["tier_context.json"]), metadata["tier_context"])
        else:
            self.assertNotIn("tier_context.json", files)

        checksums = [line.split() for line in files["checksums.txt"].decode().splitlines()]
        self.assertTrue(all(len(entry) == 2 for entry in checksums))
        self.assertEqual(
            [name for name, _ in checksums],
            sorted(name for name in files if name != "checksums.txt"),
        )
        for name, digest in checksums:
            self.assertEqual(digest, hashlib.sha256(files[name]).hexdigest())

    def test_echoes_real_bundle_context_with_deterministic_zip_bytes(self):
        archives = self.remember(Path(tempfile.mkdtemp()))
        pilot_bundle, pilot_context = self._write_fixture(
            archives, "pilot", "pilot_eligible.zip", pilot_study
        )
        final_bundle, final_context = self._write_fixture(
            archives, "analyze", "final.zip", analyze_study
        )
        control = archives / "control.json"
        control.write_text(json.dumps({"pilot": "eligible", "analyze": "final"}))
        Handler.archives = archives
        Handler.control = control
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            cases = (
                ("/v1/study/pilot", pilot_bundle, pilot_context, False),
                ("/v1/study/analyze", final_bundle, final_context, True),
            )
            for route, bundle, context, final in cases:
                first = self._post(server.server_port, route, bundle)
                second = self._post(server.server_port, route, bundle)
                self.assertEqual(first, second)
                self.assert_echoed_archive(first, context, final=final)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == "__main__":
    unittest.main()
