#!/usr/bin/env bash
# snapper-setup.sh - openSUSE-style automatic Btrfs snapshots on Fedora. See SNAPPER.md.
#
# NOT tested on Fedora 45. Read it first. The 'subvol' command moves data, so back up first.
#
# Usage:
#   ./snapper-setup.sh check                    # read-only: verify Btrfs and snapper state
#   ./snapper-setup.sh timers                   # root config, timeline + cleanup limits, enable timers
#   ./snapper-setup.sh home                     # also snapshot /home
#   ./snapper-setup.sh actions                  # dnf5 pre/post snapshots via the Actions plugin
#   ./snapper-setup.sh subvol <path> [nocow]    # move a directory into its own subvolume
#   ./snapper-setup.sh status
#
# Example for VM disks:
#   ./snapper-setup.sh subvol /var/lib/libvirt/images nocow

set -euo pipefail

ACTIONS_FILE="/etc/dnf/libdnf5-plugins/actions.d/snapper.actions"

log()  { printf '\033[1;34m[snapper]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

confirm() { local a; read -r -p "$1 [y/N] " a; [[ "$a" =~ ^[Yy]$ ]]; }

preflight() {
  [[ $EUID -ne 0 ]] || die "Run as your normal user. sudo is used where needed."
  [[ "$(findmnt -no FSTYPE /)" == "btrfs" ]] || die "Root filesystem is not Btrfs."
  sudo -v || die "sudo failed."
}

need_snapper() {
  command -v snapper >/dev/null || { log "Installing snapper..."; sudo dnf install -y snapper; }
}

has_config() { sudo snapper list-configs 2>/dev/null | awk 'NR>2 {print $1}' | grep -qx "$1"; }

cmd_check() {
  log "Root filesystem: $(findmnt -no FSTYPE /)  (needs btrfs)"
  findmnt -no TARGET,FSTYPE,OPTIONS -t btrfs || true
  echo
  log "Subvolumes:"
  sudo btrfs subvolume list / 2>/dev/null || warn "Could not list subvolumes."
  echo
  command -v snapper >/dev/null && { log "snapper configs:"; sudo snapper list-configs; } || warn "snapper not installed."
  systemctl list-timers --all 2>/dev/null | grep -i snapper || warn "No snapper timers found."
  [[ -f "$ACTIONS_FILE" ]] && log "dnf Actions rule present: $ACTIONS_FILE" || warn "No dnf Actions rule installed."
  echo
  warn "/boot is normally a separate partition and is NOT covered by Btrfs snapshots."
}

cmd_timers() {
  preflight; need_snapper
  if has_config root; then
    log "Config 'root' already exists."
  else
    sudo snapper -c root create-config /
  fi
  # openSUSE-like defaults: a few hourly, a week of dailies, pre/post pairs kept for a while.
  sudo snapper -c root set-config \
    TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes \
    TIMELINE_LIMIT_HOURLY=5 TIMELINE_LIMIT_DAILY=7 \
    TIMELINE_LIMIT_WEEKLY=0 TIMELINE_LIMIT_MONTHLY=0 TIMELINE_LIMIT_YEARLY=0 \
    NUMBER_CLEANUP=yes NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5
  sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
  log "Timers enabled."
  systemctl list-timers --all | grep -i snapper || true
  sudo snapper -c root create -c number -d "snapper-setup: baseline"
}

cmd_home() {
  preflight; need_snapper
  findmnt -no FSTYPE /home | grep -qx btrfs || die "/home is not on Btrfs."
  if has_config home; then
    log "Config 'home' already exists."
  else
    sudo snapper -c home create-config /home
  fi
  sudo snapper -c home set-config \
    TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes \
    TIMELINE_LIMIT_HOURLY=3 TIMELINE_LIMIT_DAILY=5 \
    TIMELINE_LIMIT_WEEKLY=0 TIMELINE_LIMIT_MONTHLY=0 TIMELINE_LIMIT_YEARLY=0
  log "/home is now snapshotted. Snapshots are NOT backups (same disk), see BACKUP.md."
}

cmd_actions() {
  preflight; need_snapper
  sudo dnf install -y libdnf5-plugin-actions
  if [[ -f "$ACTIONS_FILE" ]]; then
    warn "$ACTIONS_FILE already exists."
    confirm "Back it up and overwrite?" || die "Aborted."
    sudo cp -a "$ACTIONS_FILE" "${ACTIONS_FILE}.bak.$(date +%s)"
  fi
  sudo mkdir -p "$(dirname "$ACTIONS_FILE")"
  # Format: callback_name:package_filter:direction:options:command
  # The pre rule stores snapper's snapshot number in tmp.snapper_pre_number for the post rule.
  # Verify the syntax against `man libdnf5-actions` on your system before relying on it.
  sudo tee "$ACTIONS_FILE" >/dev/null <<'EOF'
# Snapper pre/post snapshots around dnf5 transactions (managed by snapper-setup.sh)
pre_transaction::::/usr/bin/sh -c echo\ "tmp.snapper_pre_number=$(snapper\ create\ -t\ pre\ -c\ number\ -p\ -d\ dnf-transaction)"
post_transaction::::/usr/bin/sh -c snapper\ create\ -t\ post\ -c\ number\ --pre-number\ "${tmp.snapper_pre_number}"\ -d\ dnf-transaction
EOF
  log "Wrote $ACTIONS_FILE"
  warn "Test it: sudo dnf install -y cowsay && sudo snapper -c root list   (expect a new pre/post pair)"
  warn "If it doesn't work, use scripts/dnf-snap instead (see SNAPPER.md)."
}

cmd_subvol() {
  local path="${1:-}" nocow="${2:-}"
  [[ -n "$path" ]] || die "Usage: $0 subvol <path> [nocow]"
  preflight
  [[ -d "$path" ]] || die "$path is not a directory."
  [[ "$(findmnt -no FSTYPE -T "$path")" == "btrfs" ]] || die "$path is not on Btrfs."

  if sudo btrfs subvolume show "$path" >/dev/null 2>&1 && [[ "$(stat -c %i "$path")" == "256" ]]; then
    log "$path is already a subvolume."
    return 0
  fi

  warn "This will: stop services using $path, move its contents into a new subvolume, and keep the original as ${path}.old."
  warn "Back up first. Free space needed: about the size of $path."
  confirm "Continue for $path?" || die "Aborted."

  if [[ "$path" == /var/lib/libvirt/images* ]]; then
    command -v virsh >/dev/null && [[ -z "$(virsh -c qemu:///system list --state-running --name 2>/dev/null | tr -d '[:space:]')" ]] \
      || die "Running VMs detected (or virsh unavailable). Shut all VMs down first."
    sudo systemctl stop libvirtd.service libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket 2>/dev/null || true
    sudo systemctl stop virtqemud.service virtqemud.socket virtqemud-ro.socket virtqemud-admin.socket 2>/dev/null || true
  fi

  sudo mv "$path" "${path}.old"
  sudo btrfs subvolume create "$path"
  if [[ "$nocow" == "nocow" ]]; then
    sudo chattr +C "$path"   # must be set while the directory is empty
    log "Copy-on-write disabled for new files in $path."
  fi
  sudo chown --reference="${path}.old" "$path"
  sudo chmod --reference="${path}.old" "$path"
  # --reflink=never so nocow files are really rewritten as nocow.
  sudo cp -a --reflink=never "${path}.old/." "$path/"
  sudo restorecon -R "$path" || warn "restorecon failed; check SELinux labels on $path."

  if [[ "$path" == /var/lib/libvirt/images* ]]; then
    sudo systemctl start libvirtd.service 2>/dev/null || sudo systemctl start virtqemud.socket 2>/dev/null || true
  fi

  log "Done. Verify everything works, then delete the old copy: sudo rm -rf ${path}.old"
  warn "Note: nocow disables checksums and compression for those files."
}

cmd_status() {
  command -v snapper >/dev/null || die "snapper not installed."
  sudo snapper list-configs
  echo
  sudo snapper -c root list | tail -n 15
  echo
  systemctl list-timers --all | grep -i snapper || true
  sudo btrfs filesystem usage / 2>/dev/null | head -n 12 || true
}

case "${1:-}" in
  check)   cmd_check ;;
  timers)  cmd_timers ;;
  home)    cmd_home ;;
  actions) cmd_actions ;;
  subvol)  shift; cmd_subvol "$@" ;;
  status)  cmd_status ;;
  *) sed -n '2,17p' "$0"; exit 1 ;;
esac
