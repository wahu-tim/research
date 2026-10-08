# Cool Things to Do with Your Fedora Install

Companion to the [setup guide](SETUP.md) and [software guide](SOFTWARE.md). These ideas come from general Fedora knowledge and were **not verified on Fedora 45**. Check package names and support first.

## Make it resilient

- **Btrfs rollbacks from the boot menu** with `grub-btrfs`. A broken update becomes a snapshot boot.
- **Restic or Borg backups** to an external drive or cloud, on a systemd timer.
- **Atomic variants** (Silverblue, Kinoite, CoreOS) are immutable with built-in rollback. Try them in a VM first.

## Build your own lab

- **Isolated research network.** Create host-only networks in libvirt, then run vulnerable targets (Metasploitable, DVWA, HackTheBox VMs) alongside Kali.
- **Disposable analysis VMs.** Clone from a snapshot, detonate a sample, roll back. No shared folders, host-only network.
- **Distrobox "personas"** (Kali, Arch, Ubuntu, Debian). They share your home directory but keep dependencies separate.
- **Local AI.** Ollama or llama.cpp on the AMD GPU for local code help. Check ROCm support for your specific card first.

## Make the system yours

- **GNOME extensions:** Forge or Pop Shell (tiling), Dash to Dock, Blur My Shell. Confirm each supports GNOME 51.
- **Dotfiles in git,** managed with `chezmoi` or GNU Stow, so a reinstall is one command.
- **A reproducible setup script.** Turn the README checklist into a script (or Ansible playbook).
- **Launcher and shortcuts:** Ulauncher or GNOME's built-in options.

## Security extras

- **WireGuard or Tailscale** for a private tunnel to your lab and home network.
- **Tor or Mullvad Browser** in a separate profile for research.
- **YubiKey** for SSH, `sudo` and LUKS unlock (`pam_u2f`, `systemd-cryptenroll`).
- **Auditd rules** to log what runs on the host.
- **Wireshark capture group** so you can capture without root.

## Hardware and performance

- **`tuned` profiles** for performance or power saving.
- **AMD GPU monitoring:** `radeontop` or `nvtop`.
- **Gaming (Steam, Proton).** Fedora 44 reportedly ships NTSYNC for Wine and Proton. Unconfirmed whether that carries to 45.

## Fun

- **Windows apps** in a VM, or with Wine and Bottles.
- **Home server on the same box:** Jellyfin, Pi-hole and Home Assistant as Podman Quadlets.
- **Retro and emulation:** RetroArch from Flathub.

## What is COPR?

**COPR** ("Cool Other Package Repo") is Fedora's community build service. Anyone with a Fedora account can package software, build RPMs on Fedora's infrastructure and publish their own repo. It's similar to Ubuntu PPAs or the Arch AUR.

```bash
sudo dnf copr enable <owner>/<project>
sudo dnf install <package>
sudo dnf copr disable <owner>/<project>
dnf copr list
```

On dnf5 the `copr` command comes from a plugin. If it's missing, install `dnf5-plugins`.

**Good for:** software not yet in Fedora's repos, newer versions than Fedora ships, nightly and git builds.

**The catch:**

- It's unofficial. Fedora doesn't vet COPR packages, and the owner can push any update. On a research host you are trusting that one maintainer with root-level installs.
- Maintainers can abandon a repo or skip a Fedora release.
- Packaging bugs go to the owner, not Fedora.

**Advice:** check the owner, project page, build history and source before enabling one. Prefer official repos, RPM Fusion, Flathub or the vendor's own repo, and keep your COPR list short.

## Suggested next projects

1. The research lab: a host-only network plus Kali plus a vulnerable target.
2. Dotfiles plus a setup script, so a rebuild is trivial.
