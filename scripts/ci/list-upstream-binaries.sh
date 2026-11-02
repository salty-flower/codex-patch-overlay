#!/usr/bin/env bash
set -euo pipefail

upstream="$(cd "$1" && pwd)"
CODEX_REPO_ROOT="$upstream" PYTHONPATH="$upstream/scripts" TARGET="$2" python3 - <<'PY'
import inspect
import os

from codex_package.cargo import source_binaries_for_target
from codex_package.targets import PACKAGE_VARIANTS, TARGET_SPECS

spec = TARGET_SPECS[os.environ["TARGET"]]
options = {
    name: (spec.is_linux if name == "build_bwrap" else spec.is_windows if "windows" in name or name == "build_codex_command_runner" else True)
    for name in inspect.signature(source_binaries_for_target).parameters
    if name.startswith("build_")
}
for binary in source_binaries_for_target(spec, PACKAGE_VARIANTS["codex"], **options):
    print(binary)
PY
