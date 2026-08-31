#!/bin/sh
set -e
# Keep the desktop database in sync when desktop-file-utils is present
# (harmless no-op otherwise).
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi
