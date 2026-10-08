#!/usr/bin/env bash
# audit.sh - READ-ONLY hardening check for a Fedora workstation. Changes nothing.
# See HARDENING.md. NOT tested on Fedora 45. Some checks need sudo to be accurate.
#
# Usage: ./audit.sh

set -uo pipefail

pass=0; warnc=0; fail=0

ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$*"; pass=$((pass+1)); }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$*"; warnc=$((warnc+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fail=$((fail+1)); }
hdr()  { printf '\n== %s ==\n' "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

hdr "Mandatory access control"
if have getenforce; then
  [[ "$(getenforce)" == "Enforcing" ]] && ok "SELinux enforcing" || bad "SELinux is $(getenforce)"
else
  warn "getenforce not found"
fi

hdr "Boot and disk"
if have mokutil; then
  mokutil --sb-state 2>/dev/null | grep -qi enabled && ok "Secure Boot enabled" \
    || warn "Secure Boot not enabled (TPM-bound disk unlock gives little protection without it)"
fi
if lsblk -no TYPE,FSTYPE 2>/dev/null | grep -qi 'crypt\|crypto_LUKS'; then
  ok "LUKS-encrypted volume present"
else
  warn "No LUKS volume detected"
fi

hdr "Firewall"
if have firewall-cmd && [[ "$(firewall-cmd --state 2>/dev/null)" == "running" ]]; then
  ok "firewalld running"
  zone="$(firewall-cmd --get-default-zone 2>/dev/null)"
  if [[ "$zone" == "FedoraWorkstation" ]]; then
    warn "Default zone is FedoraWorkstation (opens TCP/UDP 1025-65535). Consider 'public'."
  else
    ok "Default zone: $zone"
  fi
else
  bad "firewalld not running"
fi

hdr "Network exposure"
if have ss; then
  listeners="$(ss -tulnH 2>/dev/null | awk '{print $5}' | grep -Ev '^(127\.|\[::1\]|::1|\*%lo)' || true)"
  if [[ -z "$listeners" ]]; then
    ok "No services listening on non-loopback addresses"
  else
    warn "Listening on non-loopback addresses (review):"
    ss -tulnH 2>/dev/null | awk '{print "         " $1, $5}' | grep -Ev ' (127\.|\[::1\]|::1)' || true
  fi
fi

hdr "Remote access"
if systemctl is-active --quiet sshd 2>/dev/null; then
  warn "sshd is running. Disable it if you don't need inbound SSH."
else
  ok "sshd not running"
fi

hdr "Updates"
if systemctl list-unit-files 2>/dev/null | grep -qE 'dnf5?-automatic'; then
  systemctl is-enabled --quiet dnf5-automatic.timer 2>/dev/null \
    || systemctl is-enabled --quiet dnf-automatic.timer 2>/dev/null \
    && ok "Automatic updates timer enabled" || warn "Automatic updates installed but timer not enabled"
else
  warn "No automatic-update tooling installed"
fi

hdr "Auditing and USB control"
systemctl is-active --quiet auditd 2>/dev/null && ok "auditd running" || warn "auditd not running"
if have usbguard; then
  systemctl is-active --quiet usbguard 2>/dev/null && ok "USBGuard running" || warn "USBGuard installed but not running"
else
  warn "USBGuard not installed"
fi

hdr "Kernel settings"
chk() {  # name expected-regex description
  local v
  v="$(sysctl -n "$1" 2>/dev/null || echo unset)"
  [[ "$v" =~ $2 ]] && ok "$1 = $v" || warn "$1 = $v ($3)"
}
chk kernel.kptr_restrict '^[12]$' "hides kernel pointers"
chk kernel.dmesg_restrict '^1$' "restrict dmesg to root"
chk kernel.unprivileged_bpf_disabled '^[12]$' "limit unprivileged BPF"
chk kernel.yama.ptrace_scope '^[1-3]$' "limits ptrace; note: tightens debugger attach"

hdr "Accounts"
if [[ -r /etc/shadow ]] || sudo -n true 2>/dev/null; then
  empty="$(sudo -n awk -F: '($2=="" ){print $1}' /etc/shadow 2>/dev/null || true)"
  [[ -z "$empty" ]] && ok "No accounts with empty passwords" || bad "Empty password: $empty"
else
  warn "Skipped /etc/shadow check (needs passwordless sudo or run with sudo)"
fi

printf '\nSummary: %d pass, %d warn, %d fail\n' "$pass" "$warnc" "$fail"
[[ $fail -eq 0 ]]
