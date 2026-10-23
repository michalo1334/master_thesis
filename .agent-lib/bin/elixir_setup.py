"""Explicit, reviewed setup for the catalog's Elixir recipes."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from agent_lib import BundleError, MANIFEST, atomic_write, fields, json_text, load_yaml, read_json, safe_path


def resolve_app_dir(project, app_dir):
    """Resolve a Mix application below project without following symlink escapes."""
    if app_dir is None:
        return project
    raw = Path(app_dir)
    candidate = raw if raw.is_absolute() else project / raw
    try:
        relative = candidate.relative_to(project)
    except ValueError as error:
        raise BundleError("--app-dir must be inside the project") from error
    if not relative.parts:
        return project
    candidate = safe_path(project, str(relative))
    if not candidate.is_dir():
        raise BundleError(f"Elixir application directory does not exist: {relative}")
    try:
        candidate.resolve().relative_to(project.resolve())
    except ValueError as error:
        raise BundleError("--app-dir must resolve inside the project") from error
    return candidate


def relative_to_app(path, app_dir):
    return os.path.relpath(path, app_dir)


def execute(args, cwd):
    env = os.environ.copy()
    env["MIX_ENV"] = "dev"
    result = subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True)
    if result.returncode:
        detail = (result.stdout + "\n" + result.stderr)[-8000:]
        raise BundleError(f"Elixir setup command failed: {' '.join(args[:2])}\n{detail}")
    return result.stdout


def setup_plan(project, app_dir=None):
    project = Path(project).resolve()
    app_dir = resolve_app_dir(project, app_dir)
    manifest = read_json(safe_path(project, MANIFEST))
    selected = manifest.get("setup", [])
    if not selected:
        return {"recipes": [], "dependencies": {}, "minimum_elixir": "1.18", "credo_plugins": [],
                "approval_required": False, "recording": "not selected",
                "app_dir": str(app_dir.relative_to(project)) if app_dir != project else "."}
    if not (app_dir / "mix.exs").is_file():
        raise BundleError(f"Elixir setup requires a Mix project with mix.exs: {app_dir.relative_to(project)}")
    definitions = load_yaml(safe_path(project, ".agent-lib/elixir/recipes.yaml"))
    deps, plugins, minimum = {}, set(), (1, 18)
    for name in selected:
        if name not in definitions.get("recipes", {}):
            raise BundleError(f"Unknown installed recipe: {name}")
        recipe = definitions["recipes"][name]
        fields(recipe, ("elixir", "dependencies", "only", "runtime", "credo_plugins", "requires", "recording"), "recipe")
        minimum = max(minimum, tuple(int(x) for x in recipe["elixir"].split(".")))
        for package, version in recipe["dependencies"].items():
            if not re.fullmatch(r"[a-z][a-z0-9_]*", package) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
                raise BundleError("Recipes require package names and exact release versions")
            dependency = {"version": version, "runtime": recipe.get("runtime", False)}
            if "only" in recipe:
                if any(x not in ("dev", "test") for x in recipe["only"]):
                    raise BundleError("Development recipes support only dev/test environments")
                dependency["only"] = recipe["only"]
            if package in deps:
                if deps[package]["version"] != version:
                    raise BundleError(f"Incompatible recipe versions for {package}")
                dependency["runtime"] |= deps[package]["runtime"]
                if "only" in dependency and "only" in deps[package]:
                    dependency["only"] = sorted(set(dependency["only"]) | set(deps[package]["only"]))
                else:
                    dependency.pop("only", None)
            deps[package] = dependency
        plugins.update(recipe.get("credo_plugins", []))
    if plugins - {"ExDNA.Credo", "ExSlop"}:
        raise BundleError("Unknown Credo setup plugin")
    return {"recipes": selected, "dependencies": deps, "minimum_elixir": ".".join(map(str, minimum)),
            "credo_plugins": sorted(plugins), "approval_required": True,
            "recording": "adds a zero default; review existing overrides" if "phoenix-replay" in selected else "not selected",
            "app_dir": str(app_dir.relative_to(project)) if app_dir != project else "."}


def configure(project, app_dir=None, apply=False, runner=execute):
    project = Path(project).resolve()
    app_dir = resolve_app_dir(project, app_dir)
    plan = setup_plan(project, app_dir)
    if not apply or not plan["recipes"]:
        return plan
    version_output = runner(["elixir", "--version"], app_dir)
    match = re.search(r"Elixir (\d+)\.(\d+)", version_output)
    minimum = tuple(map(int, plan["minimum_elixir"].split(".")))
    if not match or tuple(map(int, match.groups())) < minimum:
        raise BundleError(f"Selected recipes require Elixir {plan['minimum_elixir']} or newer")
    if (app_dir == project and (project / ".git").exists() and
            runner(["git", "status", "--porcelain"], project).strip()):
        raise BundleError("Commit or stash changes before configuring application code")
    if app_dir != project and (project / ".git").exists():
        relative = app_dir.relative_to(project)
        if runner(["git", "status", "--porcelain", "--", str(relative)], project).strip():
            raise BundleError(f"Commit or stash changes in the application directory before configuring: {relative}")
    try:
        runner(["mix", "help", "igniter.install"], app_dir)
    except BundleError as error:
        raise BundleError("Igniter's installer is required. Install the igniter_new archive as documented; "
                          "agent-lib does not install global archives.") from error
    with tempfile.TemporaryDirectory(prefix="agent-lib-elixir-") as directory:
        request = Path(directory) / "request.json"
        request.write_text(json_text(plan))
        helper = safe_path(project, ".agent-lib/elixir")
        preflight = relative_to_app(helper / "preflight.exs", app_dir)
        runner(["mix", "run", "--no-start", "--no-compile", "--no-deps-check",
                         preflight, str(request)], app_dir)
        request_path = safe_path(project, ".agent-lib/state/setup-request.json")
        atomic_write(request_path, json_text(plan))
        installer = relative_to_app(helper / "installer", app_dir)
        runner(["mix", "igniter.install", f"agent_lib_elixir@path:{installer}",
                "--only", "dev,test", "--yes"], app_dir)
    runner(["mix", "deps.get"], app_dir)
    if "phoenix-replay" in plan["recipes"]:
        version = plan["dependencies"]["phoenix_replay"]["version"]
        runner(["mix", "igniter.install", f"phoenix_replay@{version}", "--yes"], app_dir)
    atomic_write(safe_path(project, ".agent-lib/setup.json"), json_text({"schema": 1, "plan": plan}))
    return {**plan, "approval_required": False, "configured": True,
            "next": "Review application changes, compile, and check the changed workflow manually. Review recording overrides before starting Phoenix."}
