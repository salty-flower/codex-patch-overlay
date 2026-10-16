# Patch Files

Patch files must be generated with `git format-patch` or `git diff --binary`.

Each carried patch must have a matching `patches/manifest.toml` entry with:

- upstream base tag
- upstream commit SHA
- upstream issue or PR link
- risk level
- current status

Patches to a locked Cargo dependency live in `[[dependency_patches]]` instead;
see the Dependency Patches section of `docs/rules/Patch-Policy.md`.
They are generated relative to the dependency's crate root.
