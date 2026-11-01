#!/usr/bin/env python3
"""Read-only audit of the Evaluation2 retirement manifest.

The audit answers one question: does any retired implementation path or name
survive in an active surface, or does a path this manifest owns still exist?

Phases
  inventory     Report what the manifest covers. Fail only on references that
                no manifest entry owns.
  pre-deletion  Every deleted file must still exist, so the owner can prove the
                inventory matched the tree. Fail on unowned references.
  post-deletion Every deleted path must be absent and no reference may remain
                outside the records this manifest classifies as historical.

The script reads files only. It opens no database, starts no service, reads no
secret, changes no file, and never deletes anything.

Exit codes: 0 clean, 1 findings, 2 usage or manifest error.
"""

from __future__ import annotations

import argparse
import json
import re
import signal
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable, Iterator

MANIFEST_RELATIVE = "docs/inprogress/evaluation2-goals/progress/06-retirement-manifest.json"
REPO_MARKER = "docs/inprogress/evaluation2-goals"

# Text surfaces the audit reads. Suffix matching keeps the scan predictable and
# skips archives, images and other binary payloads without guessing.
TEXT_SUFFIXES = {
    ".cfg",
    ".conf",
    ".ex",
    ".exs",
    ".html",
    ".js",
    ".json",
    ".lock",
    ".md",
    ".mdx",
    ".py",
    ".sh",
    ".sql",
    ".svelte",
    ".tf",
    ".tftpl",
    ".tfvars",
    ".toml",
    ".ts",
    ".txt",
    ".yaml",
    ".yml",
}
TEXT_NAMES = {
    "Dockerfile",
    "Dockerfile.dev",
    ".gitignore",
    ".dockerignore",
    "mix.lock",
    "package.json",
    "uv.lock",
}
MAX_TEXT_BYTES = 2_000_000

SEVERITIES = ("error", "warning", "note")


@dataclass
class Finding:
    check: str
    severity: str
    detail: str
    path: str | None = None
    line: int | None = None
    pattern: str | None = None

    def as_dict(self) -> dict[str, Any]:
        return {
            "check": self.check,
            "severity": self.severity,
            "detail": self.detail,
            "path": self.path,
            "line": self.line,
            "pattern": self.pattern,
        }


@dataclass
class Inventory:
    delete_files: list[dict[str, Any]] = field(default_factory=list)
    delete_trees: list[dict[str, Any]] = field(default_factory=list)
    beam_sets: list[dict[str, Any]] = field(default_factory=list)
    clean_dirs: list[dict[str, Any]] = field(default_factory=list)
    edit_targets: set[str] = field(default_factory=set)
    doc_edit_targets: set[str] = field(default_factory=set)
    keep_paths: set[str] = field(default_factory=set)
    delete_prefixes: list[str] = field(default_factory=list)

    def owns(self, relative_path: str) -> bool:
        """True when a manifest entry already accounts for the path."""
        if (
            relative_path in self.edit_targets
            or relative_path in self.doc_edit_targets
            or relative_path in self.keep_paths
        ):
            return True
        return any(
            relative_path == prefix or relative_path.startswith(prefix + "/")
            for prefix in self.delete_prefixes
        )


def find_repo_root(start: Path) -> Path:
    for candidate in (start, *start.parents):
        if (candidate / REPO_MARKER).is_dir():
            return candidate
    raise SystemExit(f"error: no repository marker {REPO_MARKER} above {start}")


def load_manifest(repo_root: Path, path: Path | None) -> dict[str, Any]:
    manifest_path = path or repo_root / MANIFEST_RELATIVE
    try:
        return json.loads(manifest_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"error: manifest not found: {manifest_path}")
    except json.JSONDecodeError as error:
        raise SystemExit(f"error: manifest is not valid JSON: {error}")


def normalise(relative: str) -> str:
    return relative.strip().rstrip("/")


def build_inventory(manifest: dict[str, Any]) -> Inventory:
    inventory = Inventory()

    for entry in manifest.get("current_documentation_edits", []):
        inventory.doc_edit_targets.add(normalise(entry["path"]))
        inventory.delete_prefixes.append(normalise(entry["path"]))

    for group in manifest["retirement_groups"]:
        if group.get("action") == "edit":
            for entry in group.get("entries", []):
                path = normalise(entry["path"])
                if entry.get("keep"):
                    inventory.keep_paths.add(path)
                else:
                    inventory.edit_targets.add(path)
                    inventory.delete_prefixes.append(path)
            continue

        for entry in group.get("entries", []):
            if entry.get("keep"):
                inventory.keep_paths.add(normalise(entry["path"]))
                continue
            _collect_entry(entry, inventory)

        for entry in group.get("delete", []):
            _collect_entry(entry, inventory)

        for symlink in group.get("symlinks", []):
            _collect_entry({"path": symlink["path"], "kind": "symlink"}, inventory)

        for entry in group.get("edit", []):
            path = normalise(entry["path"])
            if entry.get("kind") == "file_to_create":
                continue
            inventory.edit_targets.add(path)
            inventory.delete_prefixes.append(path)

        for entry in group.get("keep", []):
            inventory.keep_paths.add(normalise(entry["path"]))

    return inventory


def _collect_entry(entry: dict[str, Any], inventory: Inventory) -> None:
    path = normalise(entry["path"])
    kind = entry.get("kind", "file")

    if kind == "beam_set":
        inventory.beam_sets.append(entry)
    elif kind == "assert_clean_directory":
        inventory.clean_dirs.append(entry)
    elif kind in {"directory", "untracked_tree"}:
        inventory.delete_trees.append(entry)
        inventory.delete_prefixes.append(path)
    else:
        inventory.delete_files.append(entry)
        inventory.delete_prefixes.append(path)


def is_text_file(path: Path) -> bool:
    return path.suffix in TEXT_SUFFIXES or path.name in TEXT_NAMES


def iter_text_files(
    repo_root: Path, scan_roots: Iterable[str], exclude_paths: Iterable[str]
) -> Iterator[tuple[str, Path]]:
    excludes = [normalise(item) for item in exclude_paths]

    for root in scan_roots:
        target = repo_root / root
        if not target.exists():
            continue
        candidates = [target] if target.is_file() else sorted(target.rglob("*"))
        for candidate in candidates:
            if candidate.is_symlink() or not candidate.is_file():
                continue
            relative = candidate.relative_to(repo_root).as_posix()
            if any(relative == item or relative.startswith(item + "/") for item in excludes):
                continue
            vendored = ("node_modules", ".venv", "__pycache__", ".pytest_cache")
            if any(f"/{part}/" in f"/{relative}" for part in vendored):
                continue
            if not is_text_file(candidate):
                continue
            yield relative, candidate


def read_text(path: Path) -> str | None:
    try:
        if path.stat().st_size > MAX_TEXT_BYTES:
            return None
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None


def matches_glob(relative: str, pattern: str) -> bool:
    return Path(relative).match(pattern)


def check_manifest_shape(manifest: dict[str, Any]) -> list[Finding]:
    findings: list[Finding] = []
    required = (
        "schema_version",
        "retirement_groups",
        "native_scope_protected",
        "classification_exclusions",
        "audit",
    )
    for key in required:
        if key not in manifest:
            findings.append(Finding("manifest", "error", f"missing required key {key!r}"))
    for group in manifest.get("retirement_groups", []):
        for key in ("id", "title", "action", "rationale"):
            if key not in group:
                findings.append(
                    Finding("manifest", "error", f"group {group.get('id')!r} misses {key!r}")
                )
        if not any(section in group for section in ("entries", "delete", "edit")):
            findings.append(
                Finding("manifest", "error", f"group {group.get('id')!r} declares no path")
            )
    inventory = build_inventory(manifest)
    protected = [normalise(entry["path"]) for entry in manifest["native_scope_protected"]["paths"]]
    for entry in inventory.delete_files + inventory.delete_trees:
        retired = normalise(entry["path"])
        for path in protected:
            if path == retired or path.startswith(retired + "/"):
                findings.append(Finding("manifest_ownership_conflict", "error", "delete entry owns a protected path", path=path))
    return findings


def check_paths(
    repo_root: Path, inventory: Inventory, phase: str
) -> list[Finding]:
    findings: list[Finding] = []

    def report(check: str, detail: str, path: str, severity: str = "error") -> None:
        findings.append(Finding(check, severity, detail, path=path))

    for entry in inventory.delete_files:
        path = normalise(entry["path"])
        exists = (repo_root / path).exists() or (repo_root / path).is_symlink()
        if phase == "post-deletion" and exists:
            report("delete_path_present", "retired path still exists", path)
        elif phase == "pre-deletion" and not exists:
            report("delete_path_missing", "manifest lists a path that is absent", path, "warning")

    for entry in inventory.delete_trees:
        path = normalise(entry["path"])
        exists = (repo_root / path).exists()
        if phase == "post-deletion":
            if exists:
                report("delete_tree_present", "retired tree still exists", path)
            continue
        if not exists:
            report("delete_tree_missing", "manifest lists a tree that is absent", path, "warning")
            continue
        expected = entry.get("file_count")
        if expected:
            observed = sum(1 for item in (repo_root / path).rglob("*") if item.is_file())
            if observed != expected:
                report(
                    "tree_file_count_drift",
                    f"manifest records {expected} files, tree holds {observed}",
                    path,
                    "warning",
                )

    for entry in inventory.clean_dirs:
        path = normalise(entry["path"])
        target = repo_root / path
        if not target.exists():
            continue
        retired = [
            item.relative_to(repo_root).as_posix()
            for item in target.rglob("*")
            if "evaluation" in item.name.lower() and "evaluation2" not in item.name.lower()
        ]
        for relative in retired:
            report(
                "retired_artifact_present",
                "retired artifact in a shared cache directory",
                relative,
            )

    for entry in inventory.delete_trees:
        root = repo_root / normalise(entry["path"])
        if not root.is_dir():
            continue
        for item in root.rglob("*"):
            if "evaluation2" in item.name.lower():
                report(
                    "delete_tree_owns_native_path",
                    "a delete tree contains an Evaluation2 path; the manifest prefix is too broad",
                    item.relative_to(repo_root).as_posix(),
                )

    return findings


def check_protected(repo_root: Path, manifest: dict[str, Any]) -> list[Finding]:
    findings: list[Finding] = []
    for entry in manifest["native_scope_protected"]["paths"]:
        path = normalise(entry["path"])
        if not (repo_root / path).exists():
            findings.append(
                Finding("protected_path_missing", "error", "protected path is absent", path=path)
            )
    return findings


def check_references(
    repo_root: Path,
    manifest: dict[str, Any],
    inventory: Inventory,
    phase: str,
    verbose: bool,
) -> tuple[list[Finding], dict[str, Any]]:
    patterns = [
        (item["id"], re.compile(item["regex"]))
        for item in manifest["audit"]["reference_patterns"]
    ]
    allowed = manifest["audit"].get("allowed_reference_paths", [])
    excludes = manifest["audit"]["exclude_paths"]
    scan_roots = manifest["audit"]["scan_roots"]

    findings: list[Finding] = []
    classified = {
        "delete_target": 0,
        "edit_target": 0,
        "doc_edit": 0,
        "allowed": 0,
        "unexpected": 0,
    }
    scanned_files = 0

    for relative, path in iter_text_files(repo_root, scan_roots, excludes):
        text = read_text(path)
        if text is None:
            continue
        scanned_files += 1
        lines = text.splitlines()
        for pattern_id, pattern in patterns:
            for match in pattern.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                bucket = _classify(relative, inventory, allowed)
                classified[bucket] += 1
                if bucket == "delete_target" and phase != "post-deletion":
                    continue
                pending = bucket in {"edit_target", "doc_edit"}
                if bucket == "allowed" or (pending and phase != "post-deletion"):
                    if verbose:
                        findings.append(
                            Finding(
                                "reference_owned",
                                "note",
                                f"{pattern_id} reference in an owned pending edit",
                                path=relative,
                                line=line,
                                pattern=pattern_id,
                            )
                        )
                    continue
                findings.append(
                    Finding(
                        "retired_reference",
                        "error",
                        f"{pattern_id} reference survives: {lines[line - 1].strip()[:160]}",
                        path=relative,
                        line=line,
                        pattern=pattern_id,
                    )
                )

    return findings, {"scanned_files": scanned_files, "classified": classified}


def _classify(relative: str, inventory: Inventory, allowed: list[dict[str, str]]) -> str:
    if any(matches_glob(relative, item["glob"]) for item in allowed):
        return "allowed"
    if relative in inventory.doc_edit_targets:
        return "doc_edit"
    if relative in inventory.edit_targets:
        return "edit_target"
    if relative in inventory.keep_paths:
        return "unexpected"
    if any(
        relative == prefix or relative.startswith(prefix + "/")
        for prefix in inventory.delete_prefixes
    ):
        return "delete_target"
    return "unexpected"


def check_beams(repo_root: Path, inventory: Inventory, phase: str) -> list[Finding]:
    findings: list[Finding] = []
    for entry in inventory.beam_sets:
        directory = repo_root / normalise(entry["path"])
        if not directory.is_dir():
            continue
        retired = sorted(
            item.name
            for item in directory.glob("*.beam")
            if re.search(r"NetworkDefense\.Evaluations?(?:\.|$)|Mix\.Tasks\.Evaluation\.|NetworkDefense\.Evaluation2\.(?:Placeholder|NotImplementedError)(?:\.|$)", item.name)
        )
        observed = entry.get("observed_count")
        if phase == "post-deletion":
            for name in retired:
                findings.append(
                    Finding(
                        "retired_beam_present",
                        "error",
                        "compiled beam of a retired module",
                        path=f"{normalise(entry['path'])}/{name}",
                    )
                )
        elif observed is not None and retired and len(retired) != observed:
            findings.append(
                Finding(
                    "beam_count_drift",
                    "warning",
                    f"manifest records {observed} retired beams, directory holds {len(retired)}",
                    path=normalise(entry["path"]),
                )
            )
    return findings


def check_persisted_objects(
    repo_root: Path, manifest: dict[str, Any], phase: str
) -> list[Finding]:
    findings: list[Finding] = []
    schema_sources = [
        repo_root / "src/priv/repo/migrations/structure.sql",
        *sorted((repo_root / "src/priv/repo/migrations").glob("*.exs")),
    ]

    for group in manifest["retirement_groups"]:
        objects = group.get("schema_source_objects")
        if not objects:
            continue
        names = _schema_object_names(objects)
        texts = [
            (path.relative_to(repo_root).as_posix(), read_text(path) or "")
            for path in schema_sources
        ]
        for name in names:
            hits = [(relative, text) for relative, text in texts if name in text]
            migration_only = [
                relative
                for relative, _ in hits
                if "structure.sql" not in relative
            ]
            if phase == "post-deletion":
                for relative, text in hits:
                    line = text.count("\n", 0, text.index(name)) + 1
                    findings.append(
                        Finding(
                            "retired_schema_object_present",
                            "error",
                            f"retired schema object {name} still declared",
                            path=relative,
                            line=line,
                        )
                    )
            elif not hits:
                findings.append(
                    Finding(
                        "schema_object_unproven",
                        "warning",
                        f"schema object {name} not found in schema sources",
                    )
                )
            elif migration_only and phase == "inventory":
                findings.append(
                    Finding(
                        "schema_object_partial",
                        "note",
                        f"schema object {name} appears only in migrations",
                    )
                )

    native = manifest["audit"]["protected_patterns_that_must_survive"]
    for item in native:
        if "path" in item:
            if not (repo_root / item["path"]).exists():
                findings.append(
                    Finding(
                        "protected_path_missing",
                        "error",
                        "protected artifact is absent",
                        path=item["path"],
                    )
                )
            continue
        pattern = re.compile(item["regex"])
        hits = 0
        path = repo_root / item.get("path", "src")
        candidates = [path] if path.suffix else [item for item in path.rglob("*") if item.is_file()]
        for candidate in candidates:
            text = read_text(candidate)
            if text:
                hits += len(pattern.findall(text))
        if hits < item.get("min_hits", 1):
            findings.append(
                Finding(
                    "protected_binding_missing",
                    "error",
                    f"{item['id']} appears {hits} times, "
                    f"expected at least {item.get('min_hits', 1)}",
                )
            )

    return findings


def _schema_object_names(objects: dict[str, Any]) -> list[str]:
    names: list[str] = []
    for table in objects.get("tables", []):
        names.append(table.split(".")[-1])
    function = objects.get("function")
    if function:
        names.append(function.split(".")[-1].split("(")[0])
    trigger = objects.get("trigger")
    if trigger:
        names.append(trigger.split(".")[-1])
    names.extend(objects.get("indexes", []))
    names.extend(objects.get("constraints", []))
    return sorted(set(names))


def check_disguises(repo_root: Path, manifest: dict[str, Any]) -> list[Finding]:
    findings: list[Finding] = []
    excludes = manifest["audit"]["exclude_paths"]

    for marker in manifest["audit"]["forbidden_disguise_markers"]:
        if "regex" in marker:
            pattern = re.compile(marker["regex"])
            for relative, path in iter_text_files(
                repo_root, manifest["audit"]["scan_roots"], excludes
            ):
                text = read_text(path)
                if text is None:
                    continue
                for match in pattern.finditer(text):
                    findings.append(
                        Finding(
                            "disguise_marker",
                            "error",
                            f"{marker['id']}: {match.group(0)[:80]}",
                            path=relative,
                            line=text.count("\n", 0, match.start()) + 1,
                        )
                    )
        for glob in marker.get("globs", []):
            for candidate in repo_root.glob(glob):
                findings.append(
                    Finding(
                        "disguise_directory",
                        "error",
                        f"{marker['id']} directory present",
                        path=candidate.relative_to(repo_root).as_posix(),
                    )
                )
    return findings


def enumerate_delete_paths(
    repo_root: Path, inventory: Inventory, expand_untracked: bool
) -> list[str]:
    """List the owned paths. Trees stay summarised unless the caller expands them."""
    paths: list[str] = [normalise(entry["path"]) for entry in inventory.delete_files]
    for entry in inventory.delete_trees:
        root = repo_root / normalise(entry["path"])
        untracked = entry.get("git_tracked") is False
        if not root.is_dir():
            paths.append(normalise(entry["path"]))
            continue
        if not expand_untracked:
            count = sum(1 for item in root.rglob("*") if item.is_file())
            kind = "untracked" if untracked else "tracked"
            paths.append(
                f"{normalise(entry['path'])}/  ({count} files, {kind}, "
                "expand with --enumerate-untracked)"
            )
            continue
        paths.extend(
            sorted(
                item.relative_to(repo_root).as_posix()
                for item in root.rglob("*")
                if item.is_file()
            )
        )
    return sorted(set(paths))


def check_name_leftovers(repo_root: Path, phase: str) -> list[Finding]:
    """Guard against a renamed leftover that still carries the retired name."""
    if phase != "post-deletion":
        return []
    findings: list[Finding] = []
    retired_names = {"evaluation", "evaluations", "evaluation_compute"}
    roots = ("src/lib", "src/test", "src/priv", "src/config", "contracts", "services", "evaluation")
    for root in roots:
        target = repo_root / root
        if not target.exists():
            continue
        candidates = [target] if target.name in retired_names else []
        candidates.extend(target.rglob("*"))
        for item in candidates:
            if item.is_symlink() or item.name.lower() not in retired_names:
                continue
            findings.append(
                Finding(
                    "retired_name_leftover",
                    "error",
                    "path keeps a retired name",
                    path=item.relative_to(repo_root).as_posix(),
                )
            )
    return findings


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Read-only audit of the Evaluation2 retirement manifest.",
    )
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--manifest", type=Path, default=None)
    parser.add_argument(
        "--phase",
        choices=("inventory", "pre-deletion", "post-deletion"),
        default="inventory",
    )
    parser.add_argument("--json", action="store_true", help="emit a JSON report")
    parser.add_argument("--verbose", action="store_true", help="include owned references")
    parser.add_argument(
        "--list-delete-paths",
        action="store_true",
        help="print the exact file set this manifest owns",
    )
    parser.add_argument(
        "--enumerate-untracked",
        action="store_true",
        help="expand every owned tree in --list-delete-paths output",
    )
    args = parser.parse_args(argv)

    repo_root = find_repo_root(args.repo_root.resolve())
    manifest = load_manifest(repo_root, args.manifest)
    inventory = build_inventory(manifest)

    findings = check_manifest_shape(manifest)
    findings.extend(check_paths(repo_root, inventory, args.phase))
    findings.extend(check_protected(repo_root, manifest))
    reference_findings, reference_stats = check_references(
        repo_root, manifest, inventory, args.phase, args.verbose
    )
    findings.extend(reference_findings)
    findings.extend(check_beams(repo_root, inventory, args.phase))
    findings.extend(check_persisted_objects(repo_root, manifest, args.phase))
    findings.extend(check_disguises(repo_root, manifest))
    findings.extend(check_name_leftovers(repo_root, args.phase))

    errors = [item for item in findings if item.severity == "error"]
    warnings = [item for item in findings if item.severity == "warning"]

    report = {
        "phase": args.phase,
        "manifest": manifest.get("manifest_id"),
        "status": "clean" if not errors else "findings",
        "errors": len(errors),
        "warnings": len(warnings),
        "reference_scan": reference_stats,
        "delete_inventory": {
            "files": len(inventory.delete_files),
            "trees": len(inventory.delete_trees),
            "beam_sets": len(inventory.beam_sets),
            "edit_targets": len(inventory.edit_targets),
        },
        "findings": [item.as_dict() for item in findings],
    }

    if args.list_delete_paths:
        for path in enumerate_delete_paths(repo_root, inventory, args.enumerate_untracked):
            print(path)

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(f"phase: {args.phase}  status: {report['status']}")
        print(
            "delete inventory: {files} files, {trees} trees, {beam_sets} beam sets, "
            "{edit_targets} edit targets".format(**report["delete_inventory"])
        )
        print(
            "reference scan: {scanned_files} files, classified {classified}".format(
                **reference_stats
            )
        )
        for item in findings:
            location = f"{item.path}:{item.line}" if item.path and item.line else (item.path or "-")
            print(f"  [{item.severity}] {item.check} {location} :: {item.detail}")
        if not errors:
            print("no error findings")

    return 0 if not errors else 1


if __name__ == "__main__":
    # A closed pipe from `| head` is not an audit failure.
    signal.signal(signal.SIGPIPE, signal.SIG_DFL) if hasattr(signal, "SIGPIPE") else None
    sys.exit(main(sys.argv[1:]))
