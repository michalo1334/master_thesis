#!/usr/bin/env python3
"""Select agent resources, synchronize them with Peru, and preserve project ownership."""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import copy
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Any

import yaml

# Keep helper imports on the same module instance when this file runs as a script.
if __name__ == "__main__":
    sys.modules.setdefault("agent_lib", sys.modules[__name__])

DEFAULT_SOURCE = "https://github.com/michalo1334/michalo-common-agent-lib.git"
SELECTION = "agent-lib.yaml"
MANIFEST = ".agent-lib/managed.json"
LOCK = ".agent-lib/lock.json"
KINDS = ("skills", "agents", "instructions", "mcp", "extensions")
ID = re.compile(r"^[a-z][a-z0-9-]*$")
BEGIN = "<!-- BEGIN agent-lib -->"
END = "<!-- END agent-lib -->"
IGNORE_BEGIN = "# BEGIN agent-lib"
IGNORE_END = "# END agent-lib"
IGNORE_RULES = "\n".join((".agent-lib/state/", ".agent-lib/backups/", ".peru/", ".pi/npm/", ".pi/git/",
                          ".pi/node_modules/", ".pi/package.json", ".pi/package-lock.json", ".pi/bun.lock",
                          ".pi/ssh-mcp/config.toml", "__pycache__/", "*.pyc"))


class BundleError(RuntimeError):
    """An invalid selection, ownership conflict, or failed command."""


def run(args, cwd=None) -> str:
    result = subprocess.run([str(a) for a in args], cwd=cwd, text=True, capture_output=True)
    if result.returncode:
        # Do not echo command arguments: repository URLs can contain credentials.
        raise BundleError(f"{Path(str(args[0])).name} failed (exit {result.returncode}): "
                          f"{result.stderr.strip() or result.stdout.strip()}")
    return result.stdout.strip()


def mapping(value, label):
    if not isinstance(value, dict) or not all(isinstance(k, str) for k in value):
        raise BundleError(f"{label} must be a mapping with string keys")
    return value


def fields(value, allowed, label):
    mapping(value, label)
    extra = set(value) - set(allowed)
    if extra:
        raise BundleError(f"Unknown {label} fields: {', '.join(sorted(extra))}")


def names(value, label):
    if not isinstance(value, list) or any(not isinstance(x, str) or not ID.fullmatch(x) for x in value):
        raise BundleError(f"{label} must be a list of resource IDs")
    if len(set(value)) != len(value):
        raise BundleError(f"Duplicate {label} IDs")
    return value


def load_yaml(path):
    try:
        # Reject duplicate keys; safe_load otherwise silently accepts the last value.
        class UniqueLoader(yaml.SafeLoader):
            pass

        def construct(loader, node, deep=False):
            result = {}
            for key_node, value_node in node.value:
                key = loader.construct_object(key_node, deep=deep)
                if not isinstance(key, str) or key in result:
                    raise BundleError(f"Duplicate or non-string YAML key in {path.name}")
                result[key] = loader.construct_object(value_node, deep=deep)
            return result

        UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, construct)
        return yaml.load(path.read_text(), Loader=UniqueLoader)
    except (OSError, yaml.YAMLError) as error:
        raise BundleError(f"Cannot read YAML: {path}: {error}") from error


def read_json(path, default=None):
    if not path.exists():
        return copy.deepcopy(default if default is not None else {})
    try:
        return mapping(json.loads(path.read_text()), str(path))
    except (OSError, ValueError) as error:
        raise BundleError(f"Cannot read JSON: {path}") from error


def safe_path(root: Path, relative: str) -> Path:
    path = Path(relative)
    if path.is_absolute() or not path.parts or any(p in ("..", ".git") for p in path.parts):
        raise BundleError(f"Unsafe path: {relative}")
    candidate = root
    for part in path.parts:
        candidate = candidate / part
        if candidate.is_symlink():
            raise BundleError(f"Refusing symlink path: {relative}")
    return candidate


def resource_path(kind, name):
    if kind == "skills":
        return f"skills/{name}"
    if kind == "agents":
        return f"agents/{name}.md"
    if kind == "instructions":
        return "instructions/AGENTS_common_lib.md" if name == "common" else f"instructions/{name}.md"
    raise BundleError(f"No file mapping for {kind}")


def resolve_selection(source: Path, selection: dict) -> dict:
    fields(selection, ("schema", "target", "source", "bundles", "custom_bundles"), "selection")
    if type(selection.get("schema")) is not int or selection["schema"] != 1 or selection.get("target") != "pi":
        raise BundleError("Supported selection schema is 1 and target is pi")
    requested = names(selection.get("bundles"), "bundles")
    if "source" in selection:
        fields(selection["source"], ("url", "ref"), "source")
        for key in ("url", "ref"):
            value = selection["source"].get(key)
            if not isinstance(value, str) or not value or value.startswith("-") or "\n" in value:
                raise BundleError(f"source.{key} must be a nonempty URL/ref, not an option")
    catalog = {}
    for path in sorted((source / "bundles").glob("*.yaml")):
        value = load_yaml(path)
        if not isinstance(value, dict) or value.get("id") != path.stem or value.get("schema") != 1:
            raise BundleError(f"Invalid bundle definition: {path.name}")
        catalog[path.stem] = value
    custom = mapping(selection.get("custom_bundles", {}), "custom_bundles")
    for name, value in custom.items():
        names([name], "custom bundles")
        if name in catalog:
            raise BundleError(f"Custom bundle shadows catalog bundle: {name}")
        catalog[name] = value
    resources = {kind: set() for kind in KINDS}
    ordered, active, setup = [], set(), set()

    def visit(name):
        if name in active:
            raise BundleError(f"Bundle dependency cycle at {name}")
        if name in ordered:
            return
        if name not in catalog:
            raise BundleError(f"Unknown bundle: {name}")
        definition = catalog[name]
        fields(definition, ("schema", "id", "requires", "resources", "setup"), f"bundle {name}")
        if definition.get("schema", 1) != 1 or definition.get("id", name) != name:
            raise BundleError(f"Invalid schema or identity in bundle {name}")
        active.add(name)
        for dependency in names(definition.get("requires", []), "requires"):
            visit(dependency)
        selected = mapping(definition.get("resources", {}), "resources")
        fields(selected, KINDS, "resources")
        for kind, entries in selected.items():
            resources[kind].update(names(entries, kind))
        setup.update(names(definition.get("setup", []), "setup"))
        active.remove(name)
        ordered.append(name)

    for name in requested:
        visit(name)
    servers = read_json(source / "mcp/mcp-adapter.json").get("mcpServers", {})
    extensions = read_json(source / "extensions/pi.json")
    if resources["mcp"]:
        resources["extensions"].add("mcp-adapter")
    if resources["agents"]:
        resources["extensions"].update(("subagents", "context-mode"))
        if set(resources["agents"]) & {"worker", "planner"}:
            resources["extensions"].update(("todos", "questions"))
    if "common" in resources["instructions"]:
        resources["skills"].update(("asd-ste100", "writing-clearly-and-concisely"))
    for kind, entries in resources.items():
        for name in entries:
            if kind == "mcp":
                exists = name in servers
            elif kind == "extensions":
                exists = name in extensions
            else:
                path = safe_path(source, resource_path(kind, name))
                exists = (path / "SKILL.md").is_file() if kind == "skills" else path.is_file()
            if not exists:
                raise BundleError(f"Unknown {kind} resource: {name}")
    if setup:
        recipes = load_yaml(source / "installers/elixir/recipes.yaml")
        for name in setup:
            if name not in recipes.get("recipes", {}):
                raise BundleError(f"Unknown setup recipe: {name}")
    return {"bundles": ordered, "resources": {k: sorted(v) for k, v in resources.items()}, "setup": sorted(setup)}


def merge_entries(current, previous, desired, label):
    """Three-way merge atomic keys. Identical pre-existing keys stay project-owned."""
    for value in (current, previous, desired):
        mapping(value, label)
    result = copy.deepcopy(current)
    owned = {}
    for key, old in previous.items():
        if key not in result or result[key] != old:
            raise BundleError(f"Ownership conflict in {label}: {key}")
        del result[key]
    for key, value in desired.items():
        if key in result:
            if result[key] != value:
                raise BundleError(f"Project configuration conflict in {label}: {key}")
            continue
        result[key] = copy.deepcopy(value)
        owned[key] = copy.deepcopy(value)
    return result, owned


def package_identity(item):
    value = item if isinstance(item, str) else mapping(item, "package").get("source")
    if not isinstance(value, str):
        raise BundleError("Package source must be a string")
    if value.startswith("npm:"):
        raw = value[4:]
        return "npm:" + (raw.rsplit("@", 1)[0] if "@" in raw[1:] else raw)
    if value.startswith("git:"):
        return value.rsplit("@", 1)[0] if "@" in value else value
    return value


def merge_list(current, previous, desired, label, identity=lambda x: x):
    def index(items):
        if not isinstance(items, list):
            raise BundleError(f"{label} must be a list")
        result = {}
        for item in items:
            key = identity(item)
            if not isinstance(key, str) or key in result:
                raise BundleError(f"Duplicate or invalid identity in {label}")
            result[key] = item
        return result
    merged, owned = merge_entries(index(current), index(previous), index(desired), label)
    return list(merged.values()), list(owned.values())


def managed_block(current, previous, desired, begin=BEGIN, end=END):
    if current.count(begin) != current.count(end) or current.count(begin) > 1:
        raise BundleError("Malformed managed instruction/ignore block")
    if begin in current:
        start, stop = current.index(begin), current.index(end) + len(end)
        old = current[start:stop]
        if previous is None or old != previous:
            raise BundleError("Ownership conflict in managed instruction/ignore block")
        return current[:start] + desired + current[stop:]
    if previous:
        raise BundleError("Ownership conflict: managed instruction/ignore block was removed")
    return current + ("\n" if current and not current.endswith("\n") else "") + desired + "\n"


def json_text(value):
    return json.dumps(value, indent=2, ensure_ascii=False) + "\n"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text() == text:
        return
    fd, temporary = tempfile.mkstemp(prefix=".agent-lib-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(text)
        if path.exists():
            os.chmod(temporary, path.stat().st_mode & 0o777)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def plan_project(source, project, selection):
    resolved = resolve_selection(source, selection)
    for name in (".agent-lib", ".pi", ".gitignore", MANIFEST, LOCK):
        safe_path(project, name)
    old = read_json(safe_path(project, MANIFEST))
    if old and old.get("schema") != 1:
        raise BundleError("Unsupported ownership manifest schema")
    if old.get("setup") and not resolved["setup"]:
        mix = safe_path(project, "mix.exs")
        if mix.exists() and ".agent-lib/elixir/installer" in mix.read_text():
            raise BundleError("Remove the agent_lib_elixir path dependency before removing its final setup bundle")
    owned = old.get("config", {})
    resources = resolved["resources"]
    moves = {}
    for kind in ("skills", "agents", "instructions"):
        for name in resources[kind]:
            source_path = resource_path(kind, name)
            target = (f".pi/skills/{name}" if kind == "skills" else f".pi/agents/{name}.md" if kind == "agents"
                      else f".agent-lib/instructions/{name}.md")
            moves[source_path] = target
    for name in ("agent-lib", "update-agent-setup"):
        moves[name] = name
    for name in ("agent_lib.py", "elixir_setup.py"):
        moves[f"scripts/{name}"] = f".agent-lib/bin/{name}"
    moves["requirements-consumer.txt"] = ".agent-lib/requirements.txt"
    if resolved["setup"]:
        moves["installers/elixir"] = ".agent-lib/elixir"
    if "ssh-mcp" in resources["mcp"]:
        moves["adapters/pi/ssh-config.toml.example"] = ".pi/ssh-mcp/config.toml.example"
    files = {}
    for relative, target in moves.items():
        origin = safe_path(source, relative)
        if not origin.exists():
            raise BundleError(f"Missing catalog file: {relative}")
        paths = sorted(origin.rglob("*")) if origin.is_dir() else [origin]
        for path in paths:
            if path.is_symlink():
                raise BundleError(f"Catalog contains symlink: {path.relative_to(source)}")
            if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc" and path.name != ".DS_Store":
                destination = str(Path(target) / path.relative_to(origin)) if origin.is_dir() else target
                safe_path(project, destination)
                files[destination] = digest(path.read_bytes())
    settings_path = safe_path(project, ".pi/settings.json")
    settings = read_json(settings_path)
    declarations = read_json(source / "extensions/pi.json")
    selected_packages = [declarations[name] for name in resources["extensions"]]
    settings["packages"], packages_owned = merge_list(settings.get("packages", []), owned.get("packages", []),
                                                     selected_packages, "packages", package_identity)
    toggles = ["-builtin:mcp"] if resources["mcp"] else []
    settings["extensions"], toggles_owned = merge_list(settings.get("extensions", []), owned.get("extensions", []),
                                                       toggles, "extensions")
    defaults = read_json(source / "adapters/pi/settings.json")
    desired_settings = {}
    for name in resources["extensions"]:
        desired_settings.update(defaults.get(name, {}))
    settings, settings_owned = merge_entries(settings, owned.get("settings", {}), desired_settings, "settings")
    writes = {".pi/settings.json": json_text(settings)}
    server_path = safe_path(project, ".pi/mcp-adapter.json")
    mcp = read_json(server_path)
    source_mcp = read_json(source / "mcp/mcp-adapter.json")
    servers, servers_owned = merge_entries(mcp.get("mcpServers", {}), owned.get("servers", {}),
                                           {name: source_mcp["mcpServers"][name] for name in resources["mcp"]}, "MCP servers")
    mcp_settings, mcp_owned = merge_entries(mcp.get("settings", {}), owned.get("mcp_settings", {}),
                                           source_mcp.get("settings", {}) if resources["mcp"] else {}, "MCP settings")
    if resources["mcp"] or server_path.exists():
        mcp.update(mcpServers=servers, settings=mcp_settings)
        writes[".pi/mcp-adapter.json"] = json_text(mcp)
    instructions = "\n\n".join((source / resource_path("instructions", name)).read_text().strip()
                                 for name in resources["instructions"])
    append_block = f"{BEGIN}\n{instructions}\n{END}" if instructions else ""
    append_path = safe_path(project, ".pi/APPEND_SYSTEM.md")
    if instructions or old.get("append_block"):
        writes[".pi/APPEND_SYSTEM.md"] = managed_block(append_path.read_text() if append_path.exists() else "",
                                                      old.get("append_block"), append_block)
    ignore_block = f"{IGNORE_BEGIN}\n{IGNORE_RULES}\n{IGNORE_END}"
    ignore_path = safe_path(project, ".gitignore")
    writes[".gitignore"] = managed_block(ignore_path.read_text() if ignore_path.exists() else "",
                                         old.get("ignore_block"), ignore_block, IGNORE_BEGIN, IGNORE_END)
    for name, content in writes.items():
        files[name] = digest(content.encode())
    for name in old.get("files", []):
        path = safe_path(project, name)
        if name not in writes:
            expected = old.get("hashes", {}).get(name)
            if expected and (not path.is_file() or digest(path.read_bytes()) != expected):
                raise BundleError(f"Ownership conflict in imported file: {name}")
    return {"resolved": resolved, "moves": moves, "files": files, "writes": writes, "previous": old,
            "config": {"packages": packages_owned, "extensions": toggles_owned, "settings": settings_owned,
                       "servers": servers_owned, "mcp_settings": mcp_owned},
            "append_block": append_block or None, "ignore_block": ignore_block}


def describe_plan(plan, project):
    previous = set(plan["previous"].get("files", []))
    current = set(plan["files"])
    changes = {"add": sorted(current - previous), "remove": sorted(previous - current), "update": []}
    for name in sorted(current & previous):
        path = safe_path(project, name)
        if not path.is_file() or digest(path.read_bytes()) != plan["files"][name]:
            changes["update"].append(name)
    return {"bundles": plan["resolved"]["bundles"], "setup": plan["resolved"]["setup"], **changes}


def sync_project(source, project, selection, revision, dry_run=False, source_url=None):
    source, project = Path(source).resolve(), Path(project).resolve()
    plan = plan_project(source, project, selection)
    summary = describe_plan(plan, project)
    if dry_run:
        return summary
    if not shutil.which("peru"):
        raise BundleError("Peru is required. Install it with uv, pipx, or Homebrew.")
    legacy = project / "peru.yaml"
    if (project / ".peru/lastimports.index").exists() and not (project / MANIFEST).exists() and legacy.exists():
        if (load_yaml(legacy) or {}).get("imports"):
            raise BundleError("Legacy Peru state found. Run the explicit migrate command first.")
    state = safe_path(project, ".agent-lib/state")
    for relative in (".agent-lib/state/operation.lock", ".agent-lib/state/peru", ".agent-lib/state/peru.yaml"):
        safe_path(project, relative)
    state.mkdir(parents=True, exist_ok=True)
    with (state / "operation.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise BundleError("Another agent-lib operation is active") from error
        plan = plan_project(source, project, selection)
        if plan["previous"] and not (state / "peru/lastimports.index").exists():
            # A fresh Git checkout has committed ownership but no local Peru index.
            # Seed that index in an empty temporary sync directory, using only files
            # whose committed hashes were checked above. Never force-write the project.
            with tempfile.TemporaryDirectory(prefix="agent-lib-ownership-") as temporary:
                base = Path(temporary)
                previous_tree, empty_target = base / "previous", base / "target"
                previous_tree.mkdir()
                empty_target.mkdir()
                rendered = {".pi/settings.json", ".pi/mcp-adapter.json", ".pi/APPEND_SYSTEM.md", ".gitignore"}
                for name in plan["previous"].get("files", []):
                    if name not in rendered:
                        target = previous_tree / name
                        target.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(project / name, target)
                seed = {"imports": {"previous": "./"}, "cp module previous": {"path": str(previous_tree)}}
                seed_path = base / "seed.yaml"
                seed_path.write_text(yaml.safe_dump(seed))
                run(["peru", "--file", seed_path, "--sync-dir", empty_target,
                     "--state-dir", state / "peru", "sync"])
        # Stage only catalog resources, never the source checkout's caches or local files.
        with tempfile.TemporaryDirectory(prefix="agent-lib-resources-") as temporary:
            staging = Path(temporary)
            for relative in plan["moves"]:
                origin, target = source / relative, staging / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                if origin.is_dir():
                    shutil.copytree(origin, target, ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".DS_Store"))
                else:
                    shutil.copy2(origin, target)
            config = {"imports": {"agent-lib|selected|pi": "./"}, "cp module agent-lib": {"path": str(staging)},
                      "rule selected": {"pick": list(plan["moves"])},
                      "rule pi": {"move": {a: b for a, b in plan["moves"].items() if a != b}}}
            config_path = state / "peru.yaml"
            atomic_write(config_path, yaml.safe_dump(config, sort_keys=False))
            # Complete all ownership checks before Peru writes any files.
            run(["peru", "--file", config_path, "--sync-dir", project, "--state-dir", state / "peru", "sync"])
        for name, content in plan["writes"].items():
            atomic_write(safe_path(project, name), content)
        lock_data = {"schema": 1, "source": source_url or "working-tree", "revision": revision}
        atomic_write(safe_path(project, LOCK), json_text(lock_data))
        manifest = {"schema": 1, "files": sorted(plan["files"]), "hashes": plan["files"],
                    "removed": sorted((set(plan["previous"].get("files", [])) |
                                       set(plan["previous"].get("removed", []))) - set(plan["files"])),
                    "config": plan["config"], "append_block": plan["append_block"],
                    "ignore_block": plan["ignore_block"], "setup": plan["resolved"]["setup"]}
        atomic_write(safe_path(project, MANIFEST), json_text(manifest))
    return summary


@contextmanager
def checkout_source(project, selection, update=False, source_tree=None):
    if source_tree is not None:
        yield Path(source_tree).resolve(), "working-tree", "working-tree"
        return
    source = selection.get("source", {"url": DEFAULT_SOURCE, "ref": "main"})
    fields(source, ("url", "ref"), "source")
    url, ref = source.get("url"), source.get("ref")
    if not all(isinstance(v, str) and v and not v.startswith("-") and "\n" not in v for v in (url, ref)):
        raise BundleError("source.url and source.ref are required")
    lock = read_json(safe_path(project, LOCK))
    if lock and not update:
        if lock.get("source") != url or not re.fullmatch(r"[0-9a-f]{40,64}", lock.get("revision", "")):
            raise BundleError("Source differs from the lock. Use update to approve a new source revision.")
        ref = lock["revision"]
    if url.startswith("."):
        url = str((project / url).resolve())
    with tempfile.TemporaryDirectory(prefix="agent-lib-source-") as directory:
        path = Path(directory)
        run(["git", "init", "-q", str(path)])
        run(["git", "fetch", "--depth=1", "--", url, ref], path)
        revision = run(["git", "rev-parse", "FETCH_HEAD"], path)
        run(["git", "-c", "advice.detachedHead=false", "checkout", "--detach", revision], path)
        yield path, revision, source["url"]


def migrate(project, apply=False):
    """Retire an exclusively agent-lib legacy import without forcing file conflicts."""
    project = Path(project).resolve()
    config_path = safe_path(project, "peru.yaml")
    config = load_yaml(config_path)
    imports = config.get("imports", {}) if isinstance(config, dict) else {}
    if imports != {"agent-lib": "./"} or "git module agent-lib" not in config:
        raise BundleError("Migration supports only the original, exclusive agent-lib import. Review mixed imports manually.")
    if not safe_path(project, ".peru/lastimports.index").exists():
        raise BundleError("Legacy Peru state is missing; ownership cannot be established safely")
    if run(["git", "status", "--porcelain"], project):
        raise BundleError("Commit or stash project changes before migration")
    if not apply:
        return {"migration": "Retire the legacy import, back up its configuration, and preserve root AGENTS.md"}
    # The old import pin must still be available. Peru checks its managed files before cleanup.
    run(["peru", "sync"], project)
    root_agents = safe_path(project, "AGENTS.md")
    instructions = root_agents.read_bytes() if root_agents.exists() else None
    backup = safe_path(project, ".agent-lib/backups/legacy")
    if backup.exists():
        raise BundleError("A legacy backup already exists. Review it before retrying migration.")
    ignore = safe_path(project, ".gitignore")
    current = ignore.read_text() if ignore.exists() else ""
    if ".agent-lib/backups/" not in current.splitlines():
        atomic_write(ignore, current + ("\n" if current and not current.endswith("\n") else "") + ".agent-lib/backups/\n")
    backup.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    backup.parent.chmod(0o700)
    backup.mkdir(mode=0o700)
    for name in ("peru.yaml", "AGENTS.md", ".pi/settings.json", ".pi/mcp-adapter.json"):
        path = safe_path(project, name)
        if path.is_file():
            target = backup / name
            target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            shutil.copy2(path, target)
            target.chmod(0o600)
    original = config_path.read_text()
    config["imports"] = {}
    atomic_write(config_path, yaml.safe_dump(config, sort_keys=False))
    try:
        run(["peru", "sync"], project)
    except BaseException:
        atomic_write(config_path, original)
        raise
    if instructions is not None:
        root_agents.write_bytes(instructions)
    return {"migration": "Legacy import retired. Review the backup; then initialize and sync selected bundles."}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("init", "plan", "sync", "update", "configure", "migrate", "validate"))
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument("--source-tree", type=Path, help="Use a local catalog for development; not a reproducible release")
    parser.add_argument("--app-dir", type=Path,
                        help="Mix application directory inside the project (configure only; default: project root)")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--yes", action="store_true", help="Approve the separate configure or migration operation")
    args = parser.parse_args(argv)
    project = args.project.resolve()
    try:
        if args.app_dir is not None and args.command != "configure":
            raise BundleError("--app-dir is supported only with configure")
        if not project.is_dir():
            raise BundleError("Project directory does not exist")
        if args.command == "init":
            path = safe_path(project, SELECTION)
            if path.exists():
                raise BundleError(f"{SELECTION} already exists")
            selection = {"schema": 1, "target": "pi", "source": {"url": DEFAULT_SOURCE, "ref": "main"}, "bundles": ["core"]}
            if not args.dry_run:
                atomic_write(path, yaml.safe_dump(selection, sort_keys=False))
            print(f"{'Would create' if args.dry_run else 'Created'} {SELECTION}. Review it, then run plan and sync.")
            return 0
        if args.command == "migrate":
            print(json_text(migrate(project, apply=args.yes and not args.dry_run)))
            return 0
        if args.command == "configure":
            from elixir_setup import configure
            print(json_text(configure(project, app_dir=args.app_dir,
                                      apply=args.yes and not args.dry_run)))
            return 0
        selection = load_yaml(safe_path(project, SELECTION))
        with checkout_source(project, selection, update=args.command == "update", source_tree=args.source_tree) as (source, revision, url):
            if args.command == "validate":
                print(json_text(resolve_selection(source, selection)))
            else:
                result = sync_project(source, project, selection, revision,
                                      dry_run=args.dry_run or args.command == "plan", source_url=url)
                result["revision"] = revision
                print(json_text(result))
        return 0
    except (BundleError, OSError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
