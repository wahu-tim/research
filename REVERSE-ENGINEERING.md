# Reverse Engineering Setup

Companion to [LAB.md](LAB.md) and [NETWORK-ANALYSIS.md](NETWORK-ANALYSIS.md). Install methods are from general knowledge and are **not verified on Fedora 45**. Check versions and package names against each project's current page.

## Rules

- Analyze only software and samples you are authorized to analyze (your own, open-source, CTF, licensed for research, or provided under an engagement).
- **Never run an untrusted binary on the host.** Static analysis on the host is fine. Execution happens in a VM on the sealed network, with a snapshot.
- Hash everything on arrival and keep a notes file per sample.

## 1. Host tools (static analysis)

```bash
sudo dnf install -y radare2 gdb strace ltrace binwalk checksec file binutils \
  hexedit xxd python3-pip java-21-openjdk-devel
```

If a package isn't found, search with `dnf search <name>` or install it in a container.

| Tool | For |
|---|---|
| **Ghidra** | Disassembler and decompiler (the main GUI tool) |
| **Cutter** | GUI for Rizin/radare2 |
| **radare2** | Scriptable disassembly in the terminal |
| **GDB + pwndbg or GEF** | Dynamic analysis and exploit dev on Linux |
| **binwalk** | Firmware and embedded file carving |
| **checksec** | Binary mitigations (PIE, NX, RELRO, canaries) |
| **ImHex** | Hex editor with pattern language |

### Ghidra

Download from the project's official GitHub releases (`NationalSecurityAgency/ghidra`), then verify the published SHA-256 before extracting.

```bash
sha256sum ghidra_*.zip           # compare with the value on the release page
mkdir -p ~/opt && unzip ghidra_*.zip -d ~/opt
~/opt/ghidra_*/ghidraRun
```

Ghidra needs a specific JDK version. Check its README for the current requirement and install a matching `java-XX-openjdk-devel`.

### Cutter and ImHex (Flatpak)

```bash
flatpak install flathub re.rizin.cutter net.werwolv.ImHex
```

### GDB plugins

Install **pwndbg** or **GEF** from their READMEs (pick one, since they conflict). Note that Fedora's default `kernel.yama.ptrace_scope` can block attaching to non-child processes. Debug processes you launch under GDB, or use `sudo gdb`. Avoid weakening the setting system-wide.

## 2. Python tooling (in a virtualenv)

Keep these out of the system Python:

```bash
python3 -m venv ~/venvs/re
. ~/venvs/re/bin/activate
pip install pwntools capstone keystone-engine unicorn ropper frida-tools angr
```

Install only what you need, since `angr` is large. Note `keystone-engine` and `unicorn` sometimes need build tools on new Python versions.

## 3. Windows analysis VM

Many samples are Windows PE files. Build a dedicated VM from [LAB.md](LAB.md):

1. Create a Windows VM from a Microsoft evaluation image (UEFI, TPM if Windows 11).
2. Update it fully, **then disconnect it** and attach only to the sealed network.
3. Install analysis tools. The Mandiant **FLARE-VM** project installs a large Windows reverse-engineering toolset with a PowerShell script. It needs internet during install, so do that step with the NAT NIC on, then snapshot, then seal it. Follow its README for current instructions and requirements.
4. Disable what you don't want (Defender is typically turned off for malware work inside a sealed VM. Do this only inside the isolated VM).
5. Snapshot as `clean-analysis-baseline`.

Typical dynamic tools there: x64dbg, Process Monitor, Process Explorer, Autoruns, API Monitor, PE-bear, dnSpy for .NET.

## 4. Workflow

1. **Intake.** Hash and record: `sha256sum sample`, `file sample`, size, source.
2. **Triage (host, no execution).**
   ```bash
   file sample; strings -n 8 sample | less; checksec --file=sample
   binwalk sample          # embedded files
   ```
3. **Static analysis.** Open in Ghidra, let auto-analysis finish, then review imports, strings and entry points. Rename functions and variables as you learn, and keep notes.
4. **Dynamic analysis (VM only).** Revert to the clean snapshot, start captures ([NETWORK-ANALYSIS.md](NETWORK-ANALYSIS.md)), run the sample, observe, then stop and revert.
5. **Write up.** Behavior, indicators (hashes, domains, mutexes, paths), and detection ideas (YARA or Sigma).

## 5. Practice targets

- Crackmes and CTF binaries (pwn and reverse categories).
- Your own small C programs, compiled with and without mitigations, then analyzed.
- Open-source software where you can compare decompiler output to the real source.

## 6. Using a local LLM as a helper

With the [Ollama setup](OLLAMA.md) you can paste decompiled functions into a local model for an explanation or a suggested name. It's useful as a second opinion. It will hallucinate, so verify against the disassembly. Keeping it local means sensitive samples don't leave your machine.

## Troubleshooting

- **Ghidra won't start:** wrong JDK version. Run `java -version` and match the README.
- **GDB can't attach:** see the ptrace note above.
- **Flatpak apps can't see your files:** grant access with Flatseal, or move samples into the app's allowed directory.
- **Frida or angr install fails:** try a supported Python version in the venv, and check each project's install notes.
