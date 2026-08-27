"""Semantic comparison of two completed evaluation exports."""

from __future__ import annotations

import json
import shutil

from .contracts import _finite, _integer, _load, _normalise_plans
from .errors import AnalysisError

#: Stable literal identity used for baseline rows, which carry no plan_id.
BASELINE = ("__baseline__",)

DATASETS = (
    "manifest",
    "graph",
    "plans",
    "trials",
    "capability_outcomes",
    "pre_attack_flow_statuses",
    "host_compromises",
    "summary",
)


def _canonical(value):
    if isinstance(value, dict):
        return tuple(sorted((key, _canonical(item)) for key, item in value.items()))
    if isinstance(value, list):
        return tuple(_canonical(item) for item in value)
    return value


def _plan_identity(plan_id: str, identities: dict[str, tuple]) -> tuple:
    pid = str(plan_id).strip()
    if not pid:
        return BASELINE
    if pid not in identities:
        raise AnalysisError(f"unknown plan in comparison: {pid}")
    return identities[pid]


def _manifest_dataset(manifest: dict) -> list:
    return [_canonical(manifest)]


def _graph_dataset(root) -> list:
    try:
        graph = json.loads((root / "graph.json").read_text())
    except (json.JSONDecodeError, OSError) as exc:
        raise AnalysisError(f"invalid graph: {exc}") from exc
    return [_canonical(graph)]


def _plans_dataset(plans: list[dict], identities: dict[str, tuple]) -> list:
    rows = []
    for plan in plans:
        identity = identities[plan["id"]]
        rows.append(
            (
                identity,
                plan.get("objective"),
                plan.get("require_pre_attack_feasibility"),
                _canonical(plan.get("used_budget")),
                _canonical(plan.get("actions")),
                plan.get("status"),
            )
        )
    return sorted(rows)


def _trials_dataset(rows: list[dict], identities: dict[str, tuple]) -> list:
    return sorted(
        (
            _plan_identity(row["plan_id"], identities),
            _integer(row["trial_index"], "trial_index"),
            _integer(row["seed"], "attack seed"),
            _finite(row["blast_radius"], "blast_radius"),
            _finite(row["mission_impact"], "mission_impact"),
        )
        for row in rows
    )


def _capabilities_dataset(rows: list[dict], identities: dict[str, tuple]) -> list:
    return sorted(
        (
            _plan_identity(row["plan_id"], identities),
            _integer(row["trial_index"], "capability trial_index"),
            _integer(row["seed"], "capability attack seed"),
            row["capability_id"].strip(),
            row["capability_name"].strip(),
            row["disrupted"].strip().lower(),
            _finite(row["impact_weight"], "impact_weight"),
        )
        for row in rows
    )


def _flows_dataset(rows: list[dict], identities: dict[str, tuple]) -> list:
    return sorted(
        (
            _plan_identity(row["plan_id"], identities),
            row["capability_id"].strip(),
            row["capability_name"].strip(),
            row["source_segment_id"].strip(),
            row["target_service_id"].strip(),
            row["available"].strip().lower(),
        )
        for row in rows
    )


def _hosts_dataset(rows: list[dict], identities: dict[str, tuple]) -> list:
    return sorted(
        (
            _plan_identity(row["plan_id"], identities),
            _integer(row["trial_index"], "host trial_index"),
            _integer(row["seed"], "host attack seed"),
            row["host_id"].strip(),
            row["host_name"].strip(),
            row["entry_host"].strip().lower(),
            row["compromised"].strip().lower(),
        )
        for row in rows
    )


def _summary_dataset(rows: list[dict], identities: dict[str, tuple]) -> list:
    return sorted(
        (
            _plan_identity(row["plan_id"], identities),
            _integer(row["trial_count"], "summary trial_count"),
            _finite(row["expected_blast_radius"], "expected_blast_radius"),
            _finite(row["median_blast_radius"], "median_blast_radius"),
            _finite(row["blast_radius_p95"], "blast_radius_p95"),
            _finite(row["blast_radius_p99"], "blast_radius_p99"),
            _finite(row["min_blast_radius"], "min_blast_radius"),
            _finite(row["max_blast_radius"], "max_blast_radius"),
        )
        for row in rows
    )


def _datasets(loaded) -> dict[str, list]:
    identities = _normalise_plans(loaded.plans)
    return {
        "manifest": _manifest_dataset(loaded.manifest),
        "graph": _graph_dataset(loaded.root),
        "plans": _plans_dataset(loaded.plans, identities),
        "trials": _trials_dataset(loaded.trials, identities),
        "capability_outcomes": _capabilities_dataset(loaded.capabilities, identities),
        "pre_attack_flow_statuses": _flows_dataset(loaded.flows, identities),
        "host_compromises": _hosts_dataset(loaded.hosts, identities),
        "summary": _summary_dataset(loaded.summary, identities),
    }


def compare(reference, candidate) -> tuple[bool, list[str]]:
    loaded = []
    try:
        loaded.append(_load(reference))
        loaded.append(_load(candidate))
        reference_datasets = _datasets(loaded[0])
        candidate_datasets = _datasets(loaded[1])
        differences = [
            name
            for name in DATASETS
            if reference_datasets[name] != candidate_datasets[name]
        ]
        return not differences, differences
    finally:
        for export in loaded:
            if export.temporary:
                shutil.rmtree(export.temporary, ignore_errors=True)


__all__ = ["DATASETS", "compare"]
