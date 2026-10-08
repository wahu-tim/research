# Security Research Lab on Fedora (KVM / libvirt)

Companion to the [setup guide](SETUP.md), [software guide](SOFTWARE.md), [extras](EXTRAS.md) and [Ollama guide](OLLAMA.md). Steps come from general Fedora, libvirt and Kali knowledge, and **none were verified on Fedora 45**. Check package names, image names and download links against the vendors' current pages.

## Ground rules

- Only attack systems you own or have written authorization to test. This lab is built from your own VMs and deliberately vulnerable training targets.
- Keep offensive tools and risky targets off the host. Everything runs in VMs.
- Isolation is strong but not perfect. VM escapes are rare, not impossible. For serious live-malware work, use a dedicated machine.
- Snapshot before you do anything destructive.

## Quick start: build script

[`scripts/build-lab.sh`](scripts/build-lab.sh) automates sections 2 and 3 below (networks and the Kali VM). It was syntax-checked but **not run on Fedora**, so read it first.

```bash
./scripts/build-lab.sh networks                         # lab + lab-sealed networks
./scripts/build-lab.sh kali ~/Downloads/kali-*.qcow2    # Kali VM from an image you downloaded and verified
./scripts/build-lab.sh all  ~/Downloads/kali-*.qcow2    # both
./scripts/build-lab.sh status                           # networks, VMs, interfaces, snapshots
./scripts/build-lab.sh teardown                         # removes lab networks and the Kali VM
```

It does not download Kali for you, asks you to confirm you verified the checksum, and is safe to re-run (it skips what already exists).

## Layout

```
Fedora host (trusted, clean)
 ├─ libvirt NAT network "default"   -> internet (updates only)
 └─ libvirt isolated network "lab"  -> no internet
      ├─ Kali VM (2 NICs: default + lab)
      ├─ Targets (Metasploitable, Windows eval, DVWA, Juice Shop...)
      └─ Optional: INetSim VM for fake internet services
```

## 1. Prepare the host

Virtualization packages are in the main guide. Confirm everything works:

```bash
sudo dnf install -y @virtualization virt-install virt-viewer
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $USER      # log out and back in
virt-host-validate qemu
virsh -c qemu:///system list --all
```

Use `qemu:///system` (system libvirt) so networks and images are shared. Add `export LIBVIRT_DEFAULT_URI=qemu:///system` to your shell profile to avoid typing `-c` each time.

**VMware note:** don't run VMware Workstation and KVM VMs at the same time. Pick one hypervisor per session.

## 2. Create the isolated lab network

An isolated libvirt network has no `<forward>` element, so guests can reach each other and the host bridge but not the internet.

Create `lab-net.xml`:

```xml
<network>
  <name>lab</name>
  <bridge name="virbr-lab" stp="on" delay="0"/>
  <ip address="10.10.10.1" netmask="255.255.255.0">
    <dhcp>
      <range start="10.10.10.100" end="10.10.10.200"/>
    </dhcp>
  </ip>
</network>
```

```bash
virsh net-define lab-net.xml
virsh net-start lab
virsh net-autostart lab
virsh net-list --all
```

For a **fully sealed** malware network, define a second network with no `<ip>` block. Then the host has no address on it either.

## 3. Kali VM

Two options from kali.org: the prebuilt **QEMU image** (fastest) or the installer ISO.

### Prebuilt image

```bash
# After downloading and verifying the checksum from kali.org:
7z x kali-linux-*-qemu-amd64.7z
sudo mv kali-linux-*.qcow2 /var/lib/libvirt/images/kali.qcow2
sudo restorecon -v /var/lib/libvirt/images/kali.qcow2

virt-install \
  --name kali \
  --memory 8192 --vcpus 4 \
  --disk /var/lib/libvirt/images/kali.qcow2 \
  --import \
  --os-variant debiantesting \
  --network network=default \
  --network network=lab \
  --graphics spice --video virtio \
  --noautoconsole
```

- Always verify the download's checksum or signature from kali.org before using it.
- Change the default credentials on first boot (see Kali's documentation for the image's defaults).
- Update inside the VM: `sudo apt update && sudo apt full-upgrade -y`.
- When you're testing and don't want internet access, bring the NAT NIC down: `virsh domif-setlink kali <interface> down`. Find interfaces with `virsh domiflist kali`.

Check the OS variant name on your system with `osinfo-query os | grep -i -E "kali|debian"`.

### Sizing

With 96 GB RAM and 16 cores you can run several VMs. Start with Kali at 8 GB / 4 vCPUs, and 2-4 GB per target.

## 4. Targets

Pick targets that match what you want to practice. Download from each project's official page and check checksums.

| Target | What it is | How to run |
|---|---|---|
| **Metasploitable 2** | Intentionally vulnerable Linux VM | Download the VM image, convert to qcow2 with `qemu-img convert`, attach to the `lab` network only |
| **Metasploitable 3** | Vulnerable Windows/Linux build | Built with Packer and Vagrant. Heavier setup |
| **Windows evaluation VMs** | Free time-limited Microsoft eval images and ISOs | Attach to `lab`. Windows 11 needs UEFI and a TPM (`--tpm backend.type=emulator`) |
| **DVWA** | Vulnerable PHP web app | Container (below) |
| **OWASP Juice Shop** | Modern vulnerable web app | Container (below) |
| **VulnHub VMs** | Community vulnerable VMs | Download, convert, attach to `lab` |
| **HackTheBox, TryHackMe** | Hosted labs | Need accounts and their own VPN. Check their rules |

Convert a downloaded disk and import it:

```bash
qemu-img convert -O qcow2 target.vmdk /var/lib/libvirt/images/target.qcow2
sudo restorecon -v /var/lib/libvirt/images/target.qcow2

virt-install --name target1 --memory 2048 --vcpus 2 \
  --disk /var/lib/libvirt/images/target1.qcow2 --import \
  --os-variant generic --network network=lab \
  --graphics vnc --noautoconsole
```

### Vulnerable web apps in containers

Run these **inside a Linux VM on the `lab` network**, not on the host. Check each project's page for the current image name.

```bash
podman run -d --name juice -p 3000:3000 docker.io/bkimminich/juice-shop
```

If you must run one on the host, bind it to localhost only (`-p 127.0.0.1:3000:3000`) and use a rootless container.

## 5. Snapshots

```bash
virsh snapshot-create-as kali --name clean-baseline
virsh snapshot-create-as target1 --name clean-baseline
virsh snapshot-list kali

# After testing:
virsh snapshot-revert target1 clean-baseline
```

Take a snapshot after the first full update, and before each exercise. Snapshots eat disk space, so delete old ones with `virsh snapshot-delete`.

## 6. Verify isolation

Do this once after setup, and again if you change anything.

- [ ] From a target VM on `lab`: `ping 8.8.8.8` fails and `ping 10.10.10.1` works (or fails, if you made a host-less network).
- [ ] From Kali with the NAT NIC down: no internet.
- [ ] From the host: `sudo ss -tulpn` shows no vulnerable services listening on external addresses.
- [ ] `virsh domiflist <vm>` shows only the networks you intend.

## 7. Malware-analysis variant (stricter)

For analyzing untrusted samples, build a separate set of VMs with extra restrictions:

- Use only the sealed lab network. **No** NAT NIC.
- No shared folders, no clipboard sharing, and no drag-and-drop. Remove the SPICE guest agent features you don't need.
- Move samples in through a read-only ISO you build for the purpose, not through a network share.
- Revert to the clean snapshot after every sample.
- For malware that needs network services to behave, run **INetSim** (or FakeNet-NG on Windows) in a separate VM on the sealed network as the fake internet.
- Never run samples on the host or on a VM that has your credentials, SSH keys or browser sessions.
- Treat anything that has run in the VM as contaminated, and delete the disk if in doubt.

## 8. Troubleshooting

- **Permission denied on a qcow2 file:** `sudo restorecon -Rv /var/lib/libvirt/images/`, and check ownership (`qemu:qemu`). Don't disable SELinux.
- **Network won't start:** `virsh net-list --all`, check the subnet doesn't overlap another network, and read `journalctl -u libvirtd`.
- **No DHCP lease in a guest:** confirm the guest NIC is on the right network with `virsh domiflist`, and that the network is active.
- **Slow VM graphics:** use `--video virtio` and install the SPICE guest tools, or use virt-manager.
- **Nested or Windows problems:** check `virt-host-validate`, and that virtualization (SVM) is enabled in BIOS.

## 9. Next steps

- Add a second Linux VM to practice pivoting between networks (two lab networks, with a router VM).
- Script the whole lab with a shell script or Ansible so you can rebuild it.
- Add Wireshark on the host bridge (`virbr-lab`) to watch lab traffic. Use the capture group from the main guide.

## Sources

General references to check against current versions:

- Fedora Docs: Getting started with virtualization
- libvirt documentation: network XML format
- Kali Linux documentation: virtual machines and the QEMU image
- OWASP Juice Shop and DVWA project pages
- Microsoft Evaluation Center
