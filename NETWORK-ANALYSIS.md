# Fake Internet and Traffic Analysis

Companion to [LAB.md](LAB.md) and [REVERSE-ENGINEERING.md](REVERSE-ENGINEERING.md). Commands are from general knowledge and are **not verified on Fedora 45**. Check each tool's current docs and package names.

Goal: watch what a sample or a vulnerable service does on the network, with no route to the real internet.

## Design

```
Sealed libvirt network "lab-sealed" (virbr-sealed, no host IP, no NAT)
  ├─ Analysis VM (Windows/Linux)  10.66.0.10   gateway + DNS -> 10.66.0.1
  └─ INetSim VM (fake internet)   10.66.0.1
Host: captures on virbr-sealed with tcpdump / Wireshark
```

The sealed network is created by [`scripts/build-lab.sh`](scripts/build-lab.sh). It has no DHCP and no host address, so use **static IPs**. Pick any private subnet and keep it consistent. `10.66.0.0/24` is used here as an example.

## 1. INetSim VM

INetSim simulates common internet services (DNS, HTTP/S, SMTP, FTP, IRC and more) so malware that "phones home" gets believable answers.

1. Create a small Debian or Ubuntu VM (1-2 GB RAM). Give it **two NICs** for setup: NAT (to install) and `lab-sealed`.
2. Install INetSim following the project's current instructions at inetsim.org (it provides a package repository for Debian-family systems).
3. **Remove the NAT NIC** after install (`virsh detach-interface` or edit the VM), leaving only `lab-sealed`.
4. Set a static IP of `10.66.0.1` on that NIC.

Edit `/etc/inetsim/inetsim.conf`:

```
service_bind_address   10.66.0.1
dns_default_ip         10.66.0.1
start_service dns
start_service http
start_service https
start_service smtp
start_service ftp
```

```bash
sudo inetsim          # logs in /var/log/inetsim/
```

Option A: set the analysis VM's DNS and default gateway to `10.66.0.1`. Option B: make the INetSim VM a router and redirect traffic so connections to any address land on INetSim (see INetSim's documentation for `iptables` redirect examples). Option B catches malware that uses hardcoded IPs. Check INetSim's docs for the exact rules.

On Windows analysis VMs, **FakeNet-NG** (Mandiant) does a similar job locally and is part of FLARE-VM. It's a lighter option when you don't want a second VM.

## 2. Capturing traffic on the host

The sealed bridge shows up as `virbr-sealed` while the network is active.

```bash
sudo dnf install -y wireshark tcpdump

# Capture to a file (works without a GUI):
sudo tcpdump -i virbr-sealed -w ~/captures/sample01.pcap

# Or in Wireshark: add yourself to the wireshark group first (re-login needed)
sudo usermod -aG wireshark $USER
wireshark -i virbr-sealed -k
```

Capture from the bridge, not from inside the VM. Malware inside the VM can't see or tamper with it.

Make a captures directory and store `.pcap` files with the sample's hash in the name.

## 3. Analysis tools

```bash
sudo dnf install -y wireshark-cli suricata mitmproxy ngrep
```

**tshark (command line):**

```bash
tshark -r sample01.pcap -q -z conv,tcp          # conversations
tshark -r sample01.pcap -Y dns -T fields -e dns.qry.name | sort -u
tshark -r sample01.pcap -Y http.request -T fields -e http.host -e http.request.uri
```

**Suricata (IDS rules against a pcap):**

```bash
sudo suricata-update                              # fetch rules (needs internet, do on the host)
mkdir -p ~/suricata-out
suricata -r sample01.pcap -l ~/suricata-out
less ~/suricata-out/fast.log
```

**Zeek (rich logs from a pcap):** Fedora may not carry a current package. Run it from the project's container image or follow zeek.org's install options.

```bash
# Example shape, check the image name and docs first:
podman run --rm -v "$PWD":/data:Z -w /data docker.io/zeek/zeek zeek -r sample01.pcap
```

**mitmproxy (HTTPS inspection):** run it as a transparent or regular proxy on the INetSim VM or a separate analysis VM, then install its CA certificate in the analysis VM so TLS traffic can be decrypted. Only do this inside the sealed lab. Certificate pinning will defeat it.

## 4. Workflow

1. Revert the analysis VM to its clean snapshot. Start INetSim (or FakeNet-NG).
2. Start the capture on the host.
3. Run the sample in the analysis VM. Wait a few minutes (some samples sleep).
4. Stop the capture and save INetSim's logs.
5. Analyze: DNS queries, HTTP requests, odd ports, beacon intervals.
   ```bash
   tshark -r sample01.pcap -q -z endpoints,ip
   ```
6. Revert the VM. Record indicators in your notes.

## 5. Indicators to look for

- DNS lookups for algorithmically generated or random-looking domains.
- Regular, timed connections (beaconing).
- HTTP with unusual User-Agent strings or base64 bodies.
- Connections to hardcoded IPs and uncommon ports.
- Uploads of data to unfamiliar hosts.

## 6. Verify isolation (every time you change something)

- [ ] `virsh domiflist <vm>` shows the analysis VM only on `lab-sealed`.
- [ ] From the analysis VM, a ping to a real internet IP fails, and DNS names resolve only to INetSim's address.
- [ ] No NAT NIC on the INetSim VM after setup.
- [ ] Host: `sudo ss -tulpn` shows nothing unexpected listening on `virbr-sealed`.

## Troubleshooting

- **`virbr-sealed` not found:** the network isn't started. `virsh net-start lab-sealed`.
- **No traffic in the capture:** capture on the correct bridge name (`ip link | grep virbr`), and make sure the VMs are on that network.
- **The VM can't reach INetSim:** check static IPs and subnets match, and that no firewall in the INetSim VM blocks traffic.
- **Sample does nothing:** it may detect the VM, sleep, or need a specific condition. Try a longer wait, or analyze it statically.
- **Wireshark won't capture as a normal user:** the `wireshark` group change needs a re-login.
