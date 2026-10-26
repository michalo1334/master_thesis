"""Generate the checked-in Final conformance fixtures.

The script posts Final member comparison requests to a running, local
evaluation compute service and stores the returned statistics. It also posts
the correction request and stores the returned Holm response. Elixir tests then
consume these files, so the tests never implement a second statistic.

Each member request is also written to a checked-in file. The Elixir test stub
matches the traffic it receives against those files, so an adapter change cannot
move the expectation with it.

Usage:
    EVALUATION_FINAL_COMPUTE_URL=http://127.0.0.1:18080 python3 gen_fixtures.py
"""

from __future__ import annotations

import json
import os
import random
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / "contracts" / "evaluation" / "final" / "v1" / "valid"
BASE_URL = os.environ.get("EVALUATION_FINAL_COMPUTE_URL", "http://127.0.0.1:18080")

STUDY_REVISION_ID = "4f4a33c6-cc8e-4ac1-b145-18647a928e49"
STUDY_EXECUTION_ID = "5a5b44d7-dd9f-4bd2-a256-29758ba39f50"
SNAPSHOT_ID = "0f9e8d7c-6b5a-4c3d-9e2f-1a2b3c4d5e6f"
FAMILY_ID = "family-example"
PLAN_COUNT = 6
ATTACKS_PER_PLAN = 10
ALPHA = 0.05
CONFIDENCE_LEVEL = 0.95
BOOTSTRAP_REPLICATES = 500
COMPARISON_SEEDS = [5101, 5102]

IDENTITIES = [
    {
        "tier": "core",
        "budget": 4,
        "alternative": "simulation_informed",
        "reference": "cvss",
        "outcome": "mission_impact",
    },
    {
        "tier": "edge",
        "budget": 6,
        "alternative": "heuristic",
        "reference": "cvss",
        "outcome": "mission_impact",
    },
]


def matrix(seed: int, low: float, high: float) -> list[dict]:
    rng = random.Random(seed)
    plans = []

    for index in range(PLAN_COUNT):
        plans.append(
            {
                "id": f"final-plan-{seed % 1000:03d}-{index + 1:02d}",
                "mission_impacts": [
                    round(rng.uniform(low, high), 3) for _ in range(ATTACKS_PER_PLAN)
                ],
            }
        )

    return plans


def provenance(seed: int) -> dict:
    return {
        "graph_revision_ids": ["graph-revision-final"],
        "model_revision": "model-final-v1",
        "collection_seed": seed,
        "source_run_ids": ["final-collection-run"],
        "environment": "conformance",
    }


def comparison_evidence(position: int) -> dict:
    identity = IDENTITIES[position]
    attack_seeds = [901 + position * 10 + offset for offset in range(ATTACKS_PER_PLAN)]

    return {
        "outcome": identity["outcome"],
        "attack_seeds": attack_seeds,
        "alternative": {
            "strategy": identity["alternative"],
            "plans": matrix(9100 + position, 1.5, 2.6),
        },
        "reference": {"strategy": "cvss", "plans": matrix(9200 + position, 3.4, 4.8)},
    }


def snapshot_payload() -> dict:
    return {
        "schema_version": 1,
        "evidence_role": "final",
        "comparisons": [
            {
                "position": position,
                "identity": identity,
                "evidence": comparison_evidence(position),
                "provenance": provenance(5000 + position),
            }
            for position, identity in enumerate(IDENTITIES)
        ],
    }


def comparison_request(position: int) -> dict:
    return {
        "schema_version": 1,
        "evidence": comparison_evidence(position),
        "resampling": {"seed": COMPARISON_SEEDS[position], "replicates": BOOTSTRAP_REPLICATES},
        "interval": {"confidence_level": CONFIDENCE_LEVEL},
        "test": {"alternative": "two_sided"},
    }


def post(path: str, payload: dict) -> dict:
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{BASE_URL}{path}", data=body, headers={"content-type": "application/json"}
    )

    with urllib.request.urlopen(request, timeout=120) as response:
        return json.loads(response.read().decode("utf-8"))


def write(relative_path: str, payload: dict) -> None:
    path = OUT / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=False) + "\n", encoding="utf-8")
    print(f"wrote {path.relative_to(ROOT)}")


def main() -> None:
    payload = snapshot_payload()

    snapshot_input = {
        "study_revision_id": STUDY_REVISION_ID,
        "phase": "final",
        "schema_version": 1,
        "family_id": FAMILY_ID,
        "payload": payload,
    }

    request = {
        "schema_version": 1,
        "evidence_role": "final",
        "method": "holm",
        "family_id": FAMILY_ID,
        "study_revision_id": STUDY_REVISION_ID,
        "study_execution_id": STUDY_EXECUTION_ID,
        "snapshot_id": SNAPSHOT_ID,
        "source_pilot_run_id": 1,
        "plan_count": PLAN_COUNT,
        "attacks_per_plan": ATTACKS_PER_PLAN,
        "expected_comparisons": IDENTITIES,
        "comparison_seeds": COMPARISON_SEEDS,
        "analysis": {
            "alpha": ALPHA,
            "confidence_level": CONFIDENCE_LEVEL,
            "test_alternative": "two_sided",
            "bootstrap_replicates": BOOTSTRAP_REPLICATES,
        },
        "assertions": {
            "final_evidence_collected_after_pilot": True,
            "pilot_observations_excluded": True,
            "collection_completed_at": "2026-02-14T09:30:00Z",
        },
    }

    responses = []
    for position in range(len(IDENTITIES)):
        member_request = comparison_request(position)
        write(f"member-requests/{position}.json", member_request)
        response = post("/v1/comparisons/corrected-crossed-bootstrap", member_request)
        responses.append(response)
        write(f"member-responses/{position}.json", response)

    correction_request = {
        "schema_version": 1,
        "family_id": FAMILY_ID,
        "method": "holm",
        "alpha": ALPHA,
        "expected_comparisons": IDENTITIES,
        "raw_results": [
            {"identity": identity, "raw_p_value": response["test"]["raw_p_value"]}
            for identity, response in zip(IDENTITIES, responses, strict=True)
        ],
    }

    correction_response = post("/v1/families/holm", correction_request)

    write("final-small.snapshot.json", snapshot_input)
    write("final-small.request.json", request)
    write("final-small.correction-request.json", correction_request)
    write("final-small.correction-response.json", correction_response)


if __name__ == "__main__":
    main()
