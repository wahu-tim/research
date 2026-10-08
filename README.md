# Fedora 45 Workstation: Dev + Security Research

A set of guides and scripts for a single-OS, bare-metal Fedora 45 install used for development and security research. Written for an AMD Ryzen 9 7950X3D, Radeon RX 7800 XT and 96 GB DDR5 machine, but most of it is hardware-neutral.

> **Status:** written before the Fedora 45 install. Commands come from web research (Fedora 41 to 44 sources) and general knowledge, and **have not been verified on Fedora 45**. Scripts were syntax-checked only. Read before you run, and expect to fix some commands.

## Start here (suggested order)

| # | Step | Guide | Script |
|---|---|---|---|
| 1 | Install and base setup | [SETUP.md](SETUP.md) | [`scripts/post-install.sh`](scripts/post-install.sh) |
| 2 | Install your apps (terminal, VS Code, VMware, Cider...) | [SOFTWARE.md](SOFTWARE.md) | |
| 3 | Back it up before you tinker | [BACKUP.md](BACKUP.md) | [`scripts/restic-backup.sh`](scripts/restic-backup.sh) |
| 4 | Harden it | [HARDENING.md](HARDENING.md) | [`scripts/audit.sh`](scripts/audit.sh) (read-only) |
| 5 | Build the research lab | [LAB.md](LAB.md) | [`scripts/build-lab.sh`](scripts/build-lab.sh) |
| 6 | Reverse engineering tools | [REVERSE-ENGINEERING.md](REVERSE-ENGINEERING.md) | |
| 7 | Fake internet and traffic analysis | [NETWORK-ANALYSIS.md](NETWORK-ANALYSIS.md) | |
| 8 | Local LLMs on the AMD GPU | [OLLAMA.md](OLLAMA.md) | |
| 9 | Ideas, tweaks, COPR explainer | [EXTRAS.md](EXTRAS.md) | |

## Quick path

```bash
git clone https://github.com/wahu-tim/research.git fedora-setup   # or the HuwaEnterprises/fedora-setup repo
cd fedora-setup
less scripts/post-install.sh          # read it first
./scripts/post-install.sh --list      # see the steps
./scripts/post-install.sh             # interactive, asks before each step
./scripts/audit.sh                    # read-only hardening check
```

## What's where

- **Guides** are Markdown files at the repo root.
- **Scripts** are in `scripts/`. They ask before changing things, refuse to run as root, and are safe to re-run where noted.
- Each guide opens with a note on how much of it is verified.

## Decisions baked into these guides

- **Fedora 45 over Ubuntu 26.10** for newer toolchains, SELinux enforcing, rootless Podman and Flatpak-first apps.
- **Secure Boot off** on this personal machine, because VMware's kernel modules are unsigned. This affects hardening, especially TPM disk unlock. See [HARDENING.md](HARDENING.md).
- **Offensive tooling lives in VMs**, not on the host. The host stays clean.
- **KVM and VMware don't run at the same time.**

## Safety and scope

These guides are for **your own machines, your own lab and authorized testing**. Don't attack systems you don't own or lack written permission to test. Malware and vulnerable targets belong in the isolated lab only.

## Contributing to yourself

When you install Fedora 45, run each guide top to bottom and fix whatever breaks. Update the "not verified" notes as you confirm things.
