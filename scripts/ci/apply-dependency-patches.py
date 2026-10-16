#!/usr/bin/env python3
"""Apply `[[dependency_patches]]` from patches/manifest.toml to Cargo's checked-out sources.

Nix patches its vendored copy in `postPatch`; plain-cargo CI and release builds use this script.
Run it after the staged workspace's Cargo home is final and before the first build that compiles
a patched crate.
"""

import argparse
import json
import subprocess
import sys
import tomllib
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import cast

REPO_ROOT = Path(__file__).resolve().parents[2]


@dataclass(frozen=True)
class DependencyPatch:
    name: str
    crate: str
    source: str
    file: Path


@dataclass(frozen=True)
class CargoPackage:
    name: str
    source: str | None
    manifest_path: Path


class Args(argparse.Namespace):
    workspace: Path = Path()
    target: str | None = None
    release: bool = False


# TOML and JSON parsers return untyped containers; narrow them to `object` items at this boundary.
def as_table(value: object, context: str) -> Mapping[str, object]:
    if not isinstance(value, dict):
        sys.exit(f"{context}: expected a table")
    table = cast("dict[object, object]", value)
    return {str(key): item for key, item in table.items()}


def as_list(value: object, context: str) -> list[object]:
    if not isinstance(value, list):
        sys.exit(f"{context}: expected a list")
    return list(cast("list[object]", value))


def as_str(table: Mapping[str, object], key: str, context: str) -> str:
    value = table.get(key)
    if not isinstance(value, str):
        sys.exit(f"{context}: missing string field {key!r}")
    return value


def load_dependency_patches() -> list[DependencyPatch]:
    manifest: object = tomllib.loads((REPO_ROOT / "patches/manifest.toml").read_text())
    entries = as_table(manifest, "manifest").get("dependency_patches", [])
    patches: list[DependencyPatch] = []
    for index, raw in enumerate(as_list(entries, "dependency_patches")):
        context = f"dependency_patches[{index}]"
        entry = as_table(raw, context)
        patches.append(
            DependencyPatch(
                name=as_str(entry, "name", context),
                crate=as_str(entry, "crate", context),
                source=as_str(entry, "source", context),
                file=REPO_ROOT / as_str(entry, "file", context),
            )
        )
    return patches


def cargo_packages(workspace: Path) -> list[CargoPackage]:
    output = subprocess.run(
        ["cargo", "metadata", "--format-version", "1"],
        cwd=workspace,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    metadata = cast(object, json.loads(output))
    packages: list[CargoPackage] = []
    for raw in as_list(as_table(metadata, "cargo metadata").get("packages"), "packages"):
        package = as_table(raw, "cargo metadata package")
        source = package.get("source")
        packages.append(
            CargoPackage(
                name=as_str(package, "name", "cargo metadata package"),
                source=source if isinstance(source, str) else None,
                manifest_path=Path(as_str(package, "manifest_path", "cargo metadata package")),
            )
        )
    return packages


def locked_package_dir(workspace: Path, patch: DependencyPatch) -> Path:
    matches = [
        package
        for package in cargo_packages(workspace)
        if package.name == patch.crate and package.source == patch.source
    ]
    if len(matches) != 1:
        sys.exit(
            f"{patch.name}: expected one {patch.crate} from {patch.source}, found {len(matches)}"
        )
    return matches[0].manifest_path.parent


def run_patch(package_dir: Path, patch: DependencyPatch, *flags: str) -> int:
    command = ["patch", "-p1", *flags, "-d", str(package_dir), "-i", str(patch.file)]
    return subprocess.run(command, check=False, capture_output="--dry-run" in flags).returncode


def apply(workspace: Path, patch: DependencyPatch, target: str | None, release: bool) -> None:
    lock_lines = (workspace / "Cargo.lock").read_text().splitlines()
    if f'source = "{patch.source}"' not in lock_lines:
        sys.exit(f"{patch.name}: Cargo.lock no longer pins {patch.source}")

    package_dir = locked_package_dir(workspace, patch)
    # A restored Cargo home can already hold the patched checkout. `-f` matters here: with
    # `--batch`, patch treats an unapplied patch as reversed and ignores `-R`.
    if run_patch(package_dir, patch, "-R", "--dry-run", "-f", "-s") == 0:
        print(f"{patch.name}: already applied to {package_dir}")
    else:
        print(f"applying {patch.name}: {package_dir}")
        if run_patch(package_dir, patch, "--forward", "--batch") != 0:
            sys.exit(f"{patch.name}: patch does not apply to {package_dir}")

    # Cargo fingerprints git dependencies by source ID, not file contents, so a cached build
    # of the unpatched crate would otherwise be reused.
    clean = ["cargo", "clean", "-p", patch.crate, *(["--release"] if release else [])]
    _ = subprocess.run(clean, cwd=workspace, check=True)
    if target:
        _ = subprocess.run([*clean, "--target", target], cwd=workspace, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    _ = parser.add_argument("--workspace", type=Path, required=True, help="Staged codex-rs.")
    _ = parser.add_argument("--target", help="Cargo target triple whose build to invalidate.")
    _ = parser.add_argument("--release", action="store_true", help="Invalidate the release build.")
    args = parser.parse_args(namespace=Args())

    workspace = args.workspace.resolve()
    for patch in load_dependency_patches():
        apply(workspace, patch, args.target, args.release)


if __name__ == "__main__":
    main()
