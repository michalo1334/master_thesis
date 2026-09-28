from __future__ import annotations

import hashlib
import shutil
import stat
import sys
import tempfile
import zipfile
from collections.abc import Iterable
from pathlib import Path

from .errors import AnalysisError, _error

MAX_ZIP_MEMBERS = 64
MAX_ZIP_BYTES = 256 * 1024 * 1024
MAX_COMPRESSED_STDIN = 256 * 1024 * 1024


def _member_mode(member: zipfile.ZipInfo) -> int:
    """Return the Unix mode bits of one ZIP member, or zero when absent."""

    return (member.external_attr >> 16) & 0xFFFF


def _safe_extract(archive: Path) -> tuple[Path, Path]:
    temporary = Path(tempfile.mkdtemp())
    root = temporary
    try:
        with zipfile.ZipFile(archive) as source:
            members = source.infolist()
            if len(members) > MAX_ZIP_MEMBERS:
                raise _error(f"ZIP member limit exceeded: {MAX_ZIP_MEMBERS}")
            total_bytes = 0
            names = set()
            for member in members:
                if member.filename in names:
                    raise _error(f"duplicate ZIP member: {member.filename}")
                names.add(member.filename)
                name = Path(member.filename)
                if name.is_absolute() or ".." in name.parts:
                    raise _error(f"unsafe ZIP member: {member.filename}")
                mode = _member_mode(member)
                if stat.S_ISLNK(mode):
                    raise _error(f"symlink ZIP member: {member.filename}")
                if mode and stat.S_IFMT(mode) and not (
                    stat.S_ISREG(mode) or stat.S_ISDIR(mode)
                ):
                    raise _error(f"unsupported ZIP member type: {member.filename}")
                if not member.is_dir():
                    total_bytes += member.file_size
                    if total_bytes > MAX_ZIP_BYTES:
                        raise _error(f"ZIP uncompressed byte limit exceeded: {MAX_ZIP_BYTES}")
            source.extractall(root, members)
    except AnalysisError:
        shutil.rmtree(temporary, ignore_errors=True)
        raise
    except Exception as exc:
        shutil.rmtree(temporary, ignore_errors=True)
        raise _error(f"invalid ZIP: {exc}") from exc
    return root, temporary


def _read_input(source: str | Path) -> tuple[Path, Path | None]:
    path = Path(source)
    if path.is_file():
        if path.suffix.lower() != ".zip":
            raise _error("input must be a ZIP or directory")
        return _safe_extract(path)
    return path, None


def verify_checksum_file(root: Path, names: Iterable[str], coverage_message: str) -> None:
    """Verify one ``checksums.txt`` file against an expected member set.

    The error messages are shared by the inner archive loader and the outer
    study loader. The caller supplies the exact message for incomplete
    coverage.
    """

    allowed = set(names)
    entries: list[str] = []
    for line in (root / "checksums.txt").read_text().splitlines():
        if not line.strip():
            raise _error("malformed checksums.txt")
        parts = line.split()
        if len(parts) != 2:
            raise _error("malformed checksums.txt")
        name, expected = parts
        if name in entries or name not in allowed or len(expected) != 64:
            raise _error(f"invalid checksum entry: {name}")
        try:
            int(expected, 16)
        except ValueError as exc:
            raise _error(f"invalid checksum entry: {name}") from exc
        path = root / name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise _error(f"checksum mismatch: {name}")
        entries.append(name)
    if set(entries) != allowed:
        raise _error(coverage_message)


def spool_stdin() -> Path:
    temporary = Path(tempfile.mkdtemp())
    path = temporary / "input.zip"
    size = 0
    try:
        with path.open("wb") as target:
            while chunk := sys.stdin.buffer.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_COMPRESSED_STDIN:
                    raise AnalysisError(f"ZIP compressed byte limit exceeded: {MAX_COMPRESSED_STDIN}")
                target.write(chunk)
        return path
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def write_result_zip(directory: Path, stream=None) -> None:
    if stream is None:
        stream = sys.stdout.buffer
    with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        paths = sorted((p for p in directory.rglob("*") if p.is_file()), key=lambda p: p.relative_to(directory).as_posix())
        for path in paths:
            info = zipfile.ZipInfo(path.relative_to(directory).as_posix(), (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o600 << 16
            archive.writestr(info, path.read_bytes())


__all__ = ["spool_stdin", "write_result_zip", "verify_checksum_file", "_read_input"]
