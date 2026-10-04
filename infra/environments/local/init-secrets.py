#!/usr/bin/env python3

import json
import os
import secrets
import stat
import subprocess
import sys
from pathlib import Path

script_directory = Path(__file__).resolve().parent
terraform = script_directory / "terraform.sh"
expression = "jsonencode([local.secret_mount_path, local.required_secret_files])\n"
try:
    result = subprocess.run(
        [terraform, "console", "-no-color"],
        cwd=script_directory,
        input=expression,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    encoded = json.loads(result.stdout.strip())
    secret_directory, required_files = json.loads(encoded)
except (OSError, subprocess.CalledProcessError, json.JSONDecodeError, TypeError, ValueError) as error:
    print(f"Could not read required secret paths from Terraform: {error}", file=sys.stderr)
    sys.exit(1)

if not isinstance(secret_directory, str) or not os.path.isabs(secret_directory):
    print("Terraform returned an invalid secret directory.", file=sys.stderr)
    sys.exit(1)
if not isinstance(required_files, list) or not required_files:
    print("Terraform returned an invalid required secret file list.", file=sys.stderr)
    sys.exit(1)

root = Path(secret_directory)

def validate_directory(path):
    if path.exists() or path.is_symlink():
        info = path.lstat()
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            raise RuntimeError(f"Unsafe secret directory: {path}")
        if stat.S_IMODE(info.st_mode) & 0o077:
            raise RuntimeError(f"Secret directory has group or other permissions: {path}")
    else:
        path.mkdir(mode=0o700)

try:
    validate_directory(root)
    for filename in required_files:
        if not isinstance(filename, str) or not filename or os.path.isabs(filename):
            raise RuntimeError("Terraform returned an unsafe secret filename.")
        relative = Path(filename)
        if any(part in ("", ".", "..") for part in filename.split("/")):
            raise RuntimeError(f"Terraform returned an unsafe secret filename: {filename}")

        parent = root
        for part in relative.parts[:-1]:
            parent = parent / part
            validate_directory(parent)

        target = parent / relative.name
        if target.exists() or target.is_symlink():
            info = target.lstat()
            if not stat.S_ISREG(info.st_mode):
                raise RuntimeError(f"Unsafe existing secret file: {target}")
            if stat.S_IMODE(info.st_mode) & 0o077:
                raise RuntimeError(f"Existing secret file has group or other permissions: {target}")
            continue

        descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        try:
            with os.fdopen(descriptor, "w") as secret_file:
                secret_file.write(secrets.token_hex(32))
                secret_file.write("\n")
        except BaseException:
            target.unlink(missing_ok=True)
            raise
except (OSError, RuntimeError) as error:
    print(f"Could not initialize local secrets: {error}", file=sys.stderr)
    sys.exit(1)

print(f"Initialized {len(required_files)} required secret files in {root}.")
