# Software Installation Guide (Fedora 45)

Companion to the [setup guide](README.md). Install methods are from web research on Fedora 41 to 44 sources and general knowledge. **None were verified on Fedora 45**, so check package names and repo support for your release.

Rule of thumb: native RPM or official vendor repo for system-level tools, Flatpak for desktop apps, containers for everything else.

## Terminal

Fedora's default is **Ptyxis**, which is fine. Options if you want more:

| Terminal | Install | Notes |
|---|---|---|
| **Ghostty** | `sudo dnf copr enable scottames/ghostty && sudo dnf install ghostty` | Fast, GPU-accelerated. Unofficial COPR (community maintained). Listed builds covered Fedora 41 to 43 and rawhide, so confirm 45 support. |
| Kitty | `sudo dnf install kitty` | GPU-accelerated, scriptable |
| Alacritty | `sudo dnf install alacritty` | Minimal and fast |
| WezTerm | Flatpak or upstream repo | Lua config, built-in multiplexer |

Pair it with `tmux`, `starship` and a Nerd Font.

## VS Code

Use Microsoft's official repo, not a COPR.

```bash
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo tee /etc/yum.repos.d/vscode.repo <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
sudo dnf check-update
sudo dnf install code
```

Updates arrive with `sudo dnf upgrade`. The package is named `code`.

## VMware Workstation Pro

Download from the Broadcom support portal (account required). Run the `.bundle` installer:

```bash
chmod +x VMware-Workstation-*.bundle
sudo ./VMware-Workstation-*.bundle
```

Things that commonly go wrong on Fedora:

1. **Build prerequisites.** The kernel modules (`vmmon`, `vmnet`) are compiled against your running kernel, so install headers first:
   ```bash
   sudo dnf install -y kernel-devel kernel-headers elfutils-libelf-devel gcc make
   ```
2. **Secure Boot.** The modules are unsigned, so they won't load with Secure Boot on. Either disable Secure Boot, or sign the modules (recommended, since you want it on): generate a key with `kmodgenca`, enroll it with `sudo mokutil --import`, reboot to enroll, then reinstall VMware so the modules build with that key. Check state with `mokutil --sb-state`.
3. **New kernel not supported.** Fedora moves fast, and VMware may lag. Community-patched host modules exist (for example `gleb-kun/vmware-host-modules`), but they are not VMware-supported. Review the code before building them, especially with Secure Boot enabled.
4. **KVM overlap.** You are already installing KVM/libvirt for Kali and malware VMs. Running both hypervisors at once can conflict, and I did not verify how current Workstation behaves alongside KVM on Fedora 45. If VMware gives you trouble, fall back to virt-manager (KVM) for everything.

### Fixing the vmmon / vmnet module error

The classic error is "Could not open /dev/vmmon" or "Kernel module vmmon not loaded". There are two usual causes. Find yours first:

```bash
mokutil --sb-state                 # is Secure Boot on?
sudo vmware-modconfig --console --install-all   # does the build succeed?
sudo modprobe vmmon                # does it load?
dmesg | tail                       # "Key was rejected by service" = signing problem
```

> These steps come from Fedora community threads, not Fedora 45 testing. Verify paths on your system.

**Cause A: Secure Boot rejects the unsigned modules** ("Key was rejected by service")

```bash
sudo dnf install -y akmods kernel-devel
sudo kmodgenca -a
sudo mokutil --import /etc/pki/akmods/certs/public_key.der   # set a one-time password
sudo reboot                                                    # MOK screen: Enroll MOK, enter the password
```

After the reboot, build and sign the modules:

```bash
sudo vmware-modconfig --console --install-all
for m in vmmon vmnet; do
  sudo /usr/src/kernels/$(uname -r)/scripts/sign-file sha256 \
    /etc/pki/akmods/private/private_key.priv \
    /etc/pki/akmods/certs/public_key.der $(modinfo -n $m)
done
sudo modprobe vmmon vmnet
```

You must repeat the build-and-sign step after **every kernel update**.

**Cause B: the build fails because the kernel is too new**

Use community-patched sources that match your Workstation version. Pick the branch or tag for your exact version, and review the code before building it:

```bash
git clone https://github.com/mkubecek/vmware-host-modules.git
cd vmware-host-modules
git branch -a    # choose the workstation-<your version> branch
git checkout workstation-<your version>
make
sudo make install
sudo modprobe vmmon vmnet
```

Then sign the modules as in Cause A if Secure Boot is on. `gleb-kun/vmware-host-modules` is another fork that Fedora users have reported using.

## Cider (Apple Music)

Try Flathub first:

```bash
flatpak install flathub sh.cider.Cider
```

A 2025 forum thread said the Flatpak was missing for Cider 3. If it's not on Flathub for you, use the RPM from Cider's official GitHub releases page:

```bash
sudo dnf install ./cider-*.rpm
```

An AppImage is the last resort. You need an Apple Music subscription.

## Everyday apps (Flatpak)

```bash
flatpak install flathub com.github.tchx84.Flatseal
flatpak install flathub org.signal.Signal
flatpak install flathub com.bitwarden.desktop
flatpak install flathub md.obsidian.Obsidian
flatpak install flathub com.discordapp.Discord
flatpak install flathub com.spotify.Client
```

Open **Flatseal** and tighten each app's permissions.

## Browsers

- Firefox is preinstalled.
- Chrome: install from Google's repo, or use `flatpak install flathub com.google.Chrome`.
- Keep a separate browser profile for research and for everyday use.

## Security research tools

```bash
sudo dnf install -y wireshark nmap radare2 gdb strace ltrace valgrind
```

- **Ghidra:** Flatpak or the upstream download (requires a JDK: `sudo dnf install java-21-openjdk`).
- **pwndbg or GEF:** GDB plugins, installed per their READMEs.
- **Burp Suite, Kali tooling:** run them in a Kali VM, not on the host.

## Dev containers

```bash
sudo dnf install -y podman toolbox distrobox
distrobox create --name dev --image fedora:latest
distrobox enter dev
```

## Sources

- [Fedora COPR: scottames/ghostty](https://copr.fedorainfracloud.org/coprs/scottames/ghostty)
- [Linuxiac: Install VS Code on Fedora](https://linuxiac.com/how-to-install-vs-code-on-fedora-linux/)
- [ComputingForGeeks: Install VS Code on Fedora](https://computingforgeeks.com/install-visual-studio-code-on-fedora/)
- [Linuxiac: Cider on Linux](https://linuxiac.com/how-to-listen-to-apple-music-on-linux-with-cider/)
- [Broadcom KB: VMware modules fail to load on Fedora](https://knowledge.broadcom.com/external/article/315648)
- [Broadcom KB: vmmon and Secure Boot](https://knowledge.broadcom.com/external/article/342977/kernel-module-vmmon-cannot-load-in-some.html)
- [Fedora Discussion: VMware Workstation on Fedora 39](https://discussion.fedoraproject.org/t/problem-with-vmware-workstation-pro-in-fedora-39/107803/16)
