#!/usr/bin/env bash
# restic-backup.sh - back up $HOME with restic and apply a retention policy.
# See BACKUP.md. NOT tested on Fedora 45.
#
# Config (create ~/.config/restic/env, chmod 600):
#   export RESTIC_REPOSITORY=/run/media/<you>/<drive>/restic-repo
#   export RESTIC_PASSWORD_FILE=$HOME/.config/restic/password
#
# Usage: restic-backup.sh [backup|check|snapshots]

set -euo pipefail

ENV_FILE="${HOME}/.config/restic/env"
EXCLUDES="${HOME}/.config/restic/excludes"

[[ -r "$ENV_FILE" ]] || { echo "Missing $ENV_FILE (see BACKUP.md)" >&2; exit 1; }
# shellcheck disable=SC1090
. "$ENV_FILE"

command -v restic >/dev/null || { echo "restic not installed: sudo dnf install -y restic" >&2; exit 1; }
[[ -n "${RESTIC_REPOSITORY:-}" ]] || { echo "RESTIC_REPOSITORY not set" >&2; exit 1; }

# Skip quietly when a local external drive isn't plugged in.
if [[ "$RESTIC_REPOSITORY" == /* && ! -d "$RESTIC_REPOSITORY" ]]; then
  echo "Repository path not present (drive unplugged?): $RESTIC_REPOSITORY" >&2
  exit 0
fi

cmd="${1:-backup}"

case "$cmd" in
  backup)
    args=(backup "$HOME" --one-file-system --exclude-caches)
    [[ -r "$EXCLUDES" ]] && args+=(--exclude-file "$EXCLUDES")
    restic "${args[@]}"
    restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
    ;;
  check)
    restic check
    ;;
  snapshots)
    restic snapshots
    ;;
  *)
    echo "Usage: $0 [backup|check|snapshots]" >&2
    exit 1
    ;;
esac
