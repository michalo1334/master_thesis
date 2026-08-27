"""Command line transport for analysis reports."""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

from .archive import spool_stdin, write_result_zip
from .compare import compare
from . import AnalysisError, analyze


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="mode", required=True)
    for mode in ("analyze", "pilot"):
        command = subparsers.add_parser(mode)
        command.add_argument("input")
        command.add_argument("--output", required=True)
    compare_command = subparsers.add_parser("compare")
    compare_command.add_argument("reference")
    compare_command.add_argument("candidate")
    arguments = parser.parse_args(argv)
    if arguments.mode == "compare":
        try:
            equal, differences = compare(arguments.reference, arguments.candidate)
        except (AnalysisError, OSError, zipfile.BadZipFile) as exc:
            print(str(exc), file=sys.stderr)
            return 2
        result = {"equal": equal}
        if not equal:
            result["differences"] = differences
        print(json.dumps(result))
        return 0 if equal else 1
    input_temporary = None
    output_temporary = None
    try:
        source = arguments.input
        if source == "-":
            source_path = spool_stdin()
            input_temporary = source_path.parent
            source = source_path
        if arguments.output == "-":
            output_temporary = Path(tempfile.mkdtemp())
            destination = output_temporary
        else:
            destination = Path(arguments.output)
        analyze(source, destination, arguments.mode)
        if arguments.output == "-":
            write_result_zip(destination)
        return 0
    except (AnalysisError, OSError, zipfile.BadZipFile) as exc:
        print(str(exc), file=sys.stderr)
        return 2
    finally:
        if input_temporary:
            shutil.rmtree(input_temporary, ignore_errors=True)
        if output_temporary:
            shutil.rmtree(output_temporary, ignore_errors=True)

__all__ = ["main"]
