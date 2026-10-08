#!/usr/bin/env bash
# post-install.sh - automates the checklist in SETUP.md and SOFTWARE.md
#
# NOT tested on Fedora 45. Read it first. It asks before every step.
# Written for dnf5 (Fedora 41+). Package and group names may need adjusting.
#
# Usage:
#   ./post-install.sh                 # interactive, all steps in order
#   ./post-install.sh --yes           # no per-step prompts (still refuses to run as root)
#   ./post-install.sh update flathub  # only the named steps
#   ./post-install.sh --list          # show step names
#
# Log: ~/post-install.log

set -uo pipefail

LOG="${HOME}/post-install.log"
ASSUME_YES=0
FAILED=()

STEPS=(update rpmfusion flathub snapper devtools containers virtualization vscode flatpaks shelltools sectools groups)

log()  { printf '\033[1;34m[setup]\033[0m %s\n' "$*" | tee -a "$LOG"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" | tee -a "$LOG" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

confirm() {
  [[ $ASSUME_YES -eq 1 ]] && return 0
  local ans
  read -r -p "$1 [Y/n] " ans
  [[ -z "$ans" || "$ans" =~ ^[Yy]$ ]]
}

run() {
  log "+ $*"
  "$@" >>"$LOG" 2>&1
}

preflight() {
  [[ $EUID -ne 0 ]] || die "Run as your normal user, not root. sudo is used where needed."
  [[ -r /etc/os-release ]] && . /etc/os-release
  [[ "${ID:-}" == "fedora" ]] || die "This script is for Fedora (found: ${ID:-unknown})."
  command -v dnf >/dev/null || die "dnf not found."
  sudo -v || die "sudo failed."
  : >>"$LOG"
  log "Fedora ${VERSION_ID:-?}. Logging to $LOG"
}

step_update() {
  run sudo dnf upgrade --refresh -y
  warn "A reboot is recommended after a big update."
}

step_rpmfusion() {
  local v
  v="$(rpm -E %fedora)"
  run sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${v}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${v}.noarch.rpm"
  # dnf5 replacement for the old 'swap': install the full ffmpeg and let it replace ffmpeg-free.
  run sudo dnf install -y ffmpeg --allowerasing
  if confirm "Install AMD hardware video decode (mesa-va-drivers-freeworld)?"; then
    run sudo dnf install -y mesa-va-drivers-freeworld --allowerasing
  fi
}

step_flathub() {
  run sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak remotes
}

step_snapper() {
  if [[ "$(findmnt -no FSTYPE /)" != "btrfs" ]]; then
    warn "Root is not Btrfs; skipping Snapper."
    return 0
  fi
  run sudo dnf install -y snapper
  if sudo snapper list-configs 2>/dev/null | grep -q '^root'; then
    log "Snapper root config already exists."
  else
    run sudo snapper -c root create-config /
  fi
  run sudo snapper -c root create -d "post-install: before changes"
}

step_devtools() {
  run sudo dnf group install -y development-tools
  run sudo dnf install -y gcc gcc-c++ clang gdb lldb git python3-pip golang rust cargo cmake make
}

step_containers() {
  run sudo dnf install -y podman toolbox distrobox
}

step_virtualization() {
  run sudo dnf group install -y virtualization
  run sudo dnf install -y virt-install virt-viewer
  run sudo systemctl enable --now libvirtd
}

step_vscode() {
  run sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  sudo tee /etc/yum.repos.d/vscode.repo >/dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
  run sudo dnf install -y code
}

step_flatpaks() {
  local apps=(
    com.github.tchx84.Flatseal
    org.signal.Signal
    com.bitwarden.desktop
    md.obsidian.Obsidian
  )
  for a in "${apps[@]}"; do
    if confirm "Install Flatpak $a?"; then
      run flatpak install -y flathub "$a" || FAILED+=("flatpak:$a")
    fi
  done
}

step_shelltools() {
  run sudo dnf install -y zsh fish tmux neovim ripgrep fd-find bat fzf git-delta
}

step_sectools() {
  run sudo dnf install -y wireshark nmap radare2 strace ltrace valgrind
}

step_groups() {
  # Re-login is needed for these to take effect.
  run sudo usermod -aG libvirt "$USER"
  getent group wireshark >/dev/null && run sudo usermod -aG wireshark "$USER"
  warn "Log out and back in so group changes (libvirt, wireshark) apply."
}

list_steps() { printf '%s\n' "${STEPS[@]}"; }

main() {
  local selected=()
  for arg in "$@"; do
    case "$arg" in
      --yes)  ASSUME_YES=1 ;;
      --list) list_steps; exit 0 ;;
      -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
      *) selected+=("$arg") ;;
    esac
  done
  [[ ${#selected[@]} -gt 0 ]] || selected=("${STEPS[@]}")

  preflight

  for s in "${selected[@]}"; do
    declare -F "step_$s" >/dev/null || { warn "Unknown step: $s"; continue; }
    if confirm "Run step '$s'?"; then
      if "step_$s"; then
        log "Step '$s' finished."
      else
        warn "Step '$s' reported errors (see $LOG)."
        FAILED+=("$s")
      fi
    else
      log "Skipped '$s'."
    fi
  done

  if [[ ${#FAILED[@]} -gt 0 ]]; then
    warn "Problems in: ${FAILED[*]}"
    exit 1
  fi
  log "All requested steps done. Reboot, then take a snapshot: sudo snapper -c root create -d 'configured baseline'"
}

main "$@"
