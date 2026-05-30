# Patch Files

Patch files must be generated with `git format-patch` or `git diff --binary`.

Each carried patch must have a matching `patches/manifest.toml` entry with:

- upstream base tag
- upstream commit SHA
- upstream issue or PR link
- risk level
- current status
