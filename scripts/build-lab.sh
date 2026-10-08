#!/usr/bin/env bash
# build-lab.sh - build the libvirt security lab described in LAB.md
#
# Creates:
#   - network "lab"        isolated, host-only (10.10.10.0/24, DHCP)
#   - network "lab-sealed" isolated, no host address (for malware analysis)
#   - Kali VM from a Kali QEMU image YOU downloaded and verified
#
# NOT tested on Fedora 45. Read it before you run it.
#
# Usage:
#   ./build-lab.sh networks
#   ./build-lab.sh kali /path/to/kali-linux-*-amd64.qcow2
#   ./build-lab.sh all /path/to/kali-linux-*-amd64.qcow2
#   ./build-lab.sh status
#   ./build-lab.sh teardown        # removes the lab networks and the kali VM
#
# Overrides (environment): KALI_NAME KALI_RAM_MB KALI_VCPUS IMAGE_DIR OS_VARIANT

set -euo pipefail

export LIBVIRT_DEFAULT_URI="qemu:///system"

KALI_NAME="${KALI_NAME:-kali}"
KALI_RAM_MB="${KALI_RAM_MB:-8192}"
KALI_VCPUS="${KALI_VCPUS:-4}"
IMAGE_DIR="${IMAGE_DIR:-/var/lib/libvirt/images}"
OS_VARIANT="${OS_VARIANT:-debiantesting}"

LAB_NET="lab"
LAB_BRIDGE="virbr-lab"
LAB_SUBNET="10.10.10"

SEALED_NET="lab-sealed"
SEALED_BRIDGE="virbr-sealed"

log()  { printf '\033[1;34m[lab]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

preflight() {
  [[ $EUID -ne 0 ]] || die "Run as your normal user, not root. The script uses sudo only where needed."
  command -v virsh >/dev/null        || die "virsh not found. Install: sudo dnf install -y @virtualization"
  command -v virt-install >/dev/null || die "virt-install not found. Install: sudo dnf install -y virt-install"
  systemctl is-active --quiet libvirtd || systemctl is-active --quiet virtqemud \
    || die "libvirt is not running. Try: sudo systemctl enable --now libvirtd"
  virsh list --all >/dev/null 2>&1 \
    || die "Cannot talk to libvirt. Add yourself to the libvirt group, then log out and in: sudo usermod -aG libvirt \$USER"
}

net_exists() { virsh net-info "$1" >/dev/null 2>&1; }

define_net() {
  local name="$1" xml="$2"
  if net_exists "$name"; then
    log "Network '$name' already exists, leaving it as is."
  else
    local tmp
    tmp="$(mktemp)"
    printf '%s\n' "$xml" > "$tmp"
    virsh net-define "$tmp" >/dev/null
    rm -f "$tmp"
    log "Defined network '$name'."
  fi
  virsh net-autostart "$name" >/dev/null
  if [[ "$(virsh net-info "$name" | awk '/^Active:/ {print $2}')" != "yes" ]]; then
    virsh net-start "$name" >/dev/null
    log "Started network '$name'."
  fi
}

build_networks() {
  # Isolated, host-only: no <forward>, so no route to the internet.
  define_net "$LAB_NET" "<network>
  <name>${LAB_NET}</name>
  <bridge name='${LAB_BRIDGE}' stp='on' delay='0'/>
  <ip address='${LAB_SUBNET}.1' netmask='255.255.255.0'>
    <dhcp><range start='${LAB_SUBNET}.100' end='${LAB_SUBNET}.200'/></dhcp>
  </ip>
</network>"

  # Sealed: no <forward> and no <ip>, so the host has no address on it either.
  # Guests need static IPs (or a DHCP server VM such as INetSim's gateway).
  define_net "$SEALED_NET" "<network>
  <name>${SEALED_NET}</name>
  <bridge name='${SEALED_BRIDGE}' stp='on' delay='0'/>
</network>"

  # The default NAT network is what gives Kali internet access for updates.
  if net_exists default; then
    [[ "$(virsh net-info default | awk '/^Active:/ {print $2}')" == "yes" ]] \
      || { virsh net-start default >/dev/null; log "Started network 'default'."; }
  else
    warn "libvirt network 'default' (NAT) not found. Kali will have no internet NIC."
  fi
}

build_kali() {
  local src="${1:-}"
  [[ -n "$src" ]]  || die "Usage: $0 kali /path/to/kali-image.qcow2"
  [[ -f "$src" ]]  || die "Image not found: $src"
  [[ "$src" == *.qcow2 ]] || die "Expected a .qcow2 file. Extract the .7z from kali.org first (7z x ...)."

  if virsh dominfo "$KALI_NAME" >/dev/null 2>&1; then
    log "VM '$KALI_NAME' already exists, skipping."
    return
  fi

  net_exists "$LAB_NET" || die "Network '$LAB_NET' missing. Run: $0 networks"

  warn "Verify this image's checksum/signature against kali.org before trusting it."
  read -r -p "Have you verified the image? [y/N] " ok
  [[ "$ok" =~ ^[Yy]$ ]] || die "Aborted. Verify the image first."

  local dest="${IMAGE_DIR}/${KALI_NAME}.qcow2"
  [[ ! -e "$dest" ]] || die "$dest already exists. Move it or set KALI_NAME."

  log "Copying image to $dest (sudo)..."
  sudo cp --reflink=auto "$src" "$dest"
  sudo chown qemu:qemu "$dest" 2>/dev/null || true
  sudo restorecon -v "$dest" >/dev/null 2>&1 || warn "restorecon failed; if the VM can't start, fix the SELinux label on $dest"

  local nets=(--network "network=${LAB_NET}")
  if net_exists default; then
    nets=(--network network=default "${nets[@]}")
  fi

  log "Creating VM '$KALI_NAME' (${KALI_RAM_MB} MB, ${KALI_VCPUS} vCPUs)..."
  virt-install \
    --name "$KALI_NAME" \
    --memory "$KALI_RAM_MB" --vcpus "$KALI_VCPUS" \
    --disk "$dest" --import \
    --os-variant "$OS_VARIANT" \
    "${nets[@]}" \
    --graphics spice --video virtio \
    --noautoconsole

  log "Done. Open it with: virt-viewer $KALI_NAME   (or virt-manager)"
  log "Change the default credentials on first boot, then update: sudo apt update && sudo apt full-upgrade -y"
  log "After updating, shut it down and take a baseline snapshot:"
  log "  virsh snapshot-create-as $KALI_NAME --name clean-baseline"
}

status() {
  log "Networks:"
  virsh net-list --all
  log "VMs:"
  virsh list --all
  if virsh dominfo "$KALI_NAME" >/dev/null 2>&1; then
    log "$KALI_NAME interfaces:"
    virsh domiflist "$KALI_NAME"
    log "$KALI_NAME snapshots:"
    virsh snapshot-list "$KALI_NAME" || true
  fi
  cat <<EOF

Isolation checklist (do this by hand):
  [ ] From a target on '${LAB_NET}': ping 8.8.8.8 fails
  [ ] From Kali with the NAT NIC down: no internet
  [ ] On the host: sudo ss -tulpn shows no vulnerable services on external addresses
EOF
}

teardown() {
  warn "This removes the '$LAB_NET' and '$SEALED_NET' networks and the '$KALI_NAME' VM including its disk."
  read -r -p "Type 'teardown' to continue: " confirm
  [[ "$confirm" == "teardown" ]] || die "Aborted."

  if virsh dominfo "$KALI_NAME" >/dev/null 2>&1; then
    virsh destroy "$KALI_NAME" >/dev/null 2>&1 || true
    virsh undefine "$KALI_NAME" --remove-all-storage --snapshots-metadata --nvram >/dev/null 2>&1 \
      || virsh undefine "$KALI_NAME" --remove-all-storage --snapshots-metadata >/dev/null 2>&1 \
      || warn "Could not fully remove '$KALI_NAME'. Check: virsh list --all"
    log "Removed VM '$KALI_NAME'."
  fi

  for n in "$LAB_NET" "$SEALED_NET"; do
    if net_exists "$n"; then
      virsh net-destroy "$n" >/dev/null 2>&1 || true
      virsh net-undefine "$n" >/dev/null
      log "Removed network '$n'."
    fi
  done
  log "Target VMs you created yourself are not touched."
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    networks) preflight; build_networks ;;
    kali)     preflight; build_kali "${2:-}" ;;
    all)      preflight; build_networks; build_kali "${2:-}" ;;
    status)   preflight; status ;;
    teardown) preflight; teardown ;;
    *) sed -n '2,19p' "$0"; exit 1 ;;
  esac
}

main "$@"
