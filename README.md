# Fedora 45 Setup: Dev Workstation + Security Research

Quick setup guide for a single-OS, bare-metal Fedora Workstation install on an AMD GPU machine, used for development and security research.

> Fedora 45 final is targeted for ~Oct 20, 2026 (fallback Oct 27). The beta works but the final is preferable if you can wait.
> Back up your data first. The install wipes the drive.

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
- [ ] Leave Secure Boot on (Fedora supports it)

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

## Sources

- [Fedora Magazine: Announcing Fedora Linux 45 Beta](https://fedoramagazine.org/announcing-fedora-linux-45-beta/)
- [Red Hat: Fedora 45 Beta now available](https://redhat.com/en/blog/fedora-45-beta-now-available)
- [Phoronix: Ubuntu 26.10 Beta Released](https://www.phoronix.com/news/Ubuntu-26.10-Beta-Released)
