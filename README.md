# Fedora 45 Setup: Dev Workstation + Security Research

Quick setup guide for a single-OS, bare-metal Fedora Workstation install on an AMD GPU machine, used for development and security research.

> Fedora 45 final is targeted for ~Oct 20, 2026 (fallback Oct 27). The beta works but the final is preferable if you can wait.
> Back up your data first. The install wipes the drive.

See also: [SOFTWARE.md](SOFTWARE.md) for installing a terminal, VS Code, VMware Workstation, Cider and other apps, and [EXTRAS.md](EXTRAS.md) for lab, resilience and customization ideas plus an explainer on COPR, and [OLLAMA.md](OLLAMA.md) for running local LLMs on an AMD GPU.

## Why Fedora over Ubuntu 26.10 for this use

- SELinux enforcing and rootless Podman by default make a safer host baseline.
- Newer toolchains (GCC 16.2, Go 1.27, Python 3.15, glibc 2.44) help with building and fuzzing.
- Flatpak/Flathub is first-class, with no Snap.
- Btrfs snapshots make beta updates easy to roll back.
- Ubuntu advantages: larger tutorial and tool ecosystem, and AMD's primary ROCm target.

Caveats: kernel and Plasma versions for Fedora 45 came from a single secondary source. The oo7 secret store and kmscon console are new in this release, so test your credential flows early.

## 1. Before installing

- [ ] Update BIOS/UEFI
- [ ] Download **Fedora Workstation** from fedoraproject.org and write it with Fedora Media Writer
- [ ] Secure Boot: Fedora supports it, but on a personal machine running VMware you can leave it off. That skips module signing (see [SOFTWARE.md](SOFTWARE.md)).

## 2. Install (Anaconda)

- [ ] Use the whole disk with the default **Btrfs** layout
- [ ] **Enable disk encryption (LUKS)** with a strong passphrase. It cannot be added cleanly later.
- [ ] Skip Stratis

## 3. First boot

```bash
sudo dnf upgrade --refresh -y
sudo reboot
```

Enable RPM Fusion and install multimedia codecs:

```bash
sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
```

Check Flathub is enabled:

```bash
flatpak remotes
```

## 4. Snapshots (beta safety net)

```bash
sudo dnf install -y snapper
sudo snapper -c root create-config /
sudo snapper -c root create -d "fresh install"
```

Snapshot before big updates. `btrfs-assistant` or `snapper-gui` give a GUI.

## 5. Dev toolchain

```bash
sudo dnf install -y @development-tools gcc gcc-c++ clang gdb lldb git python3-pip golang rust cargo cmake
sudo dnf install -y podman toolbox distrobox
```

Keep language runtimes and project dependencies in Toolbx/Distrobox containers so the host stays clean.

## 6. Virtualization (Kali and malware labs)

```bash
sudo dnf install -y @virtualization
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $USER
```

Log out and back in, then use virt-manager.

- Build a **Kali or Parrot VM** for offensive tooling.
- For untrusted samples, use a separate snapshotted VM with no shared folders and a host-only network.

## 7. Security research tools (host)

Keep the host lean:

```bash
sudo dnf install -y wireshark nmap radare2 gdb strace ltrace valgrind
```

For reverse engineering, install Ghidra (Flatpak or upstream) and pwndbg or GEF for GDB.

Leave **SELinux enforcing** (`getenforce`). Troubleshoot denials with `ausearch -m avc` rather than disabling it.

## 8. Hardening and basics

- [ ] Firewall running: `sudo firewall-cmd --state`
- [ ] Password manager set up
- [ ] Test git credentials, SSH agent and VS Code sign-in (oo7 is new)
- [ ] SSH key (and hardware key if used)

## 9. AMD GPU

Open Mesa drivers work out of the box. For compute or cracking, check ROCm support for your specific GPU before relying on it:

```bash
dnf search rocm
```

## 10. Final snapshot

```bash
sudo snapper -c root create -d "configured baseline"
```

## 11. Advanced tweaks (optional)

> Commands here are from general Fedora knowledge and were **not verified on Fedora 45**. Check package and option names first (Fedora 41+ uses dnf5).

**Skip:** `mitigations=off`, disabling SELinux, custom kernels. They cost the hardening that makes Fedora a good research host, for little gain.

**System**

- [ ] Faster DNF: add `max_parallel_downloads=10` and `defaultyes=True` to `/etc/dnf/dnf.conf`
- [ ] Firmware: `sudo fwupdmgr refresh && sudo fwupdmgr update`
- [ ] AMD hardware video decode (RPM Fusion): `sudo dnf swap mesa-va-drivers mesa-va-drivers-freeworld --allowerasing`
- [ ] Confirm defaults rather than tuning them: zram swap (`zramctl`), Btrfs zstd compression (`mount | grep btrfs`), weekly fstrim

**Shell and dev quality of life**

```bash
sudo dnf install -y zsh fish tmux neovim ripgrep fd-find bat fzf git-delta
```

- [ ] Add `starship` (prompt), `direnv` + `mise` (per-project tool versions)
- [ ] One Distrobox container per project

**Security hardening**

- [ ] USBGuard to authorize USB devices
- [ ] Automatic security-only updates (dnf5 `automatic` equivalent; confirm package name)
- [ ] TPM2 disk unlock: `systemd-cryptenroll` (keep your recovery passphrase)
- [ ] DNS over TLS via systemd-resolved
- [ ] OpenSCAP scan to see where you stand (one blog reports a stock Fedora 44 cloud image at ~75/100 on CIS Level 1 Server)
- [ ] Limit Flatpak permissions with Flatseal
- [ ] Skip fapolicyd on a research workstation; it can break tooling

## Sources

- [ComputingForGeeks: Security hardening Fedora](https://computingforgeeks.com/security-hardening-fedora/)
- [Fedora Discussion: Securing Fedora on a laptop](https://discussion.fedoraproject.org/t/securing-fedora-installation-on-my-laptop/196912)
- [DebugPoint: Things to do after installing Fedora](https://www.debugpoint.com/10-things-to-do-fedora-37-after-install) (older, Fedora 37)
- [Fedora Magazine: Announcing Fedora Linux 45 Beta](https://fedoramagazine.org/announcing-fedora-linux-45-beta/)
- [Red Hat: Fedora 45 Beta now available](https://redhat.com/en/blog/fedora-45-beta-now-available)
- [Phoronix: Ubuntu 26.10 Beta Released](https://www.phoronix.com/news/Ubuntu-26.10-Beta-Released)
