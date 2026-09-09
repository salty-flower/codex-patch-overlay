#!/usr/bin/env nu

def main [] {
  ^nu scripts/check-editable-enter-queue.nu
  ^nu scripts/check-manifest-fields.nu
  ^nix flake check
}
