# Hardening Checklist

Hardening for a Fedora research workstation. Companion to [SETUP.md](SETUP.md). Steps come from general Fedora knowledge and a couple of hardening blog posts. **None were verified on Fedora 45.** Package names, config paths and defaults can differ on dnf5.

Script: [`scripts/audit.sh`](scripts/audit.sh) is read-only. It checks the items below and changes nothing.

```bash
./scripts/audit.sh
```

Fedora's defaults are decent: SELinux enforcing, firewalld on, rootless Podman. This checklist closes gaps without breaking your research tools. One blog reported a stock Fedora 44 cloud image at about 75/100 on CIS Level 1 Server, so defaults are a starting point.

## Your Secure Boot situation

You run with Secure Boot **off**, and VMware's unsigned modules are the reason. That has consequences:

- A TPM-bound LUKS unlock (below) is weak without Secure Boot. Anyone with physical access could boot a modified boot chain.
- To get back to a strong setup, sign the VMware modules ([SOFTWARE.md](SOFTWARE.md), "Cause A") and enable Secure Boot, or use only KVM, which needs no unsigned modules.
- If you keep Secure Boot off, treat disk encryption with a passphrase as your protection, and skip TPM auto-unlock.

## 1. Firewall

Fedora Workstation's default zone, `FedoraWorkstation`, opens TCP/UDP ports 1025-65535 for convenience. Check yours:

```bash
sudo firewall-cmd --get-default-zone
sudo firewall-cmd --list-all
```

Tighter option:

```bash
sudo firewall-cmd --set-default-zone=public
sudo firewall-cmd --runtime-to-permanent
```

Services that relied on those open ports (GNOME file sharing, KDE Connect, local dev servers reached from other machines) will stop being reachable. Open specific ports as needed: `sudo firewall-cmd --permanent --add-port=8080/tcp`. Libvirt's networks keep working.

## 2. Automatic security updates

```bash
sudo dnf install -y dnf5-plugin-automatic        # package name may differ
sudo cp /usr/share/dnf5/dnf5-plugins/automatic.conf /etc/dnf/automatic.conf   # path may differ
# edit /etc/dnf/automatic.conf: set upgrade_type = security, apply_updates = yes
sudo systemctl enable --now dnf5-automatic.timer
```

Check the actual package, config path and timer name with `dnf search automatic` and `rpm -ql <package>`. Security-only auto-updates are a trade-off: you get patches fast, and occasionally something changes under you. Snapper snapshots plus backups ([BACKUP.md](BACKUP.md)) are your safety net.

## 3. USBGuard

Blocks unknown USB devices (rogue keyboards, BadUSB-style attacks).

```bash
sudo dnf install -y usbguard
# With ALL your normal USB devices plugged in (keyboard, mouse, hubs, drives):
sudo sh -c 'usbguard generate-policy > /etc/usbguard/rules.conf'
sudo systemctl enable --now usbguard
```

**Lockout risk:** if your keyboard isn't in the generated policy, you can lose input. Generate the policy with everything plugged in, and keep a way to recover (a second keyboard on a different port, or boot from rescue media). Allow a new device later with `sudo usbguard list-devices` then `sudo usbguard allow-device <id> -p`.

## 4. DNS over TLS

`/etc/systemd/resolved.conf.d/dot.conf`:

```ini
[Resolve]
DNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net
DNSOverTLS=yes
```

```bash
sudo systemctl restart systemd-resolved
resolvectl status
```

`DNSOverTLS=yes` fails closed, so DNS breaks on networks that block port 853. Use `opportunistic` instead to fall back. Pick a resolver you trust. Libvirt's internal DNS is unaffected.

## 5. Kernel and sysctl hardening

`/etc/sysctl.d/90-hardening.conf`:

```
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.unprivileged_bpf_disabled = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
```

```bash
sudo sysctl --system
```

**Research caveats:**

- `kptr_restrict=2` and `dmesg_restrict=1` hide kernel addresses, which can hamper some kernel debugging and exploit-dev practice. Relax them temporarily for that work.
- Don't loosen `kernel.yama.ptrace_scope` globally to make GDB attach work. Debug processes you launch yourself, or use `sudo gdb`.
- `rp_filter` can drop traffic in multi-homed lab setups. If lab networking misbehaves, check it.

## 6. Auditing

```bash
sudo dnf install -y audit
sudo systemctl enable --now auditd
```

`/etc/audit/rules.d/90-local.rules`:

```
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k sudo
-w /etc/sudoers.d/ -p wa -k sudo
-w /etc/ssh/sshd_config -p wa -k ssh
```

```bash
sudo augenrules --load
sudo ausearch -k identity -ts today
```

## 7. Disk encryption

- Confirm LUKS is on: `lsblk -f`.
- Back up the LUKS header ([BACKUP.md](BACKUP.md)).
- **TPM2 unlock** (only if Secure Boot is on, see above):
  ```bash
  sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/<luks-device>
  ```
  Then add `tpm2-device=auto` to the volume's options in `/etc/crypttab` and run `sudo dracut -f`. Keep your recovery passphrase. Firmware or Secure Boot changes can invalidate the TPM binding, and you'd need the passphrase.

## 8. Services and exposure

```bash
systemctl list-unit-files --state=enabled
sudo ss -tulpn
```

- Disable what you don't use (`sshd`, `cups` if no printer, `avahi-daemon` if you don't need mDNS).
- Keep lab services bound to localhost or the lab bridge, not `0.0.0.0`.

## 9. Flatpak and app confinement

- Use **Flatseal** to remove broad permissions (filesystem=home, device=all, network) from apps that don't need them.
- Prefer Flatpak or containers for untrusted tools.

## 10. OpenSCAP scan

```bash
sudo dnf install -y openscap-scanner scap-security-guide
oscap info /usr/share/xml/scap/ssg/content/ssg-fedora-ds.xml        # list profile IDs
sudo oscap xccdf eval --profile <profile-id> \
  --report ~/oscap-report.html /usr/share/xml/scap/ssg/content/ssg-fedora-ds.xml
```

Open the HTML report and treat it as a list of ideas, not orders. Many rules are written for servers and will conflict with a workstation (and with research tooling).

## What to skip

- **fapolicyd** allow-listing: it blocks anything not packaged or trusted, so it breaks research tooling.
- Disabling SELinux or mitigations. Fix denials with `ausearch -m avc` and `audit2allow` instead.
- Copy-pasting a "mega hardening script" you haven't read.

## Re-check

Run `./scripts/audit.sh` after each change, and again after major updates.
