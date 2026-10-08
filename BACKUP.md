# Backups with restic

Snapshots (Snapper) roll back a bad update. They live on the same disk, so they are **not** backups. This guide sets up real, encrypted, versioned backups with [restic](https://restic.net). Commands are from general restic and systemd knowledge and are **not verified on Fedora 45**. Test a restore before you trust any of it.

Script: [`scripts/restic-backup.sh`](scripts/restic-backup.sh)

## What to back up

| Back up | Skip |
|---|---|
| `$HOME` (documents, code, dotfiles, SSH/GPG keys) | `~/.cache`, trash, build output |
| `/etc` customizations (copy the ones you changed) | VM disks in `/var/lib/libvirt/images` (back up golden images separately) |
| A list of installed packages | Ollama models and container images (re-downloadable) |
| LUKS header and recovery keys (see below) | Anything you can rebuild from the lab script |

## 1. Install and prepare the target

```bash
sudo dnf install -y restic
```

Use an external drive, formatted with LUKS and mounted somewhere stable (GNOME Disks does this). Keep the drive unplugged when you're not backing up. Ransomware and mistakes can't reach it then. For cloud, restic supports S3-compatible storage, Backblaze B2, SFTP and, through `rclone`, most others. See restic's docs for the repo URL format.

## 2. Create the repository

```bash
mkdir -p ~/.config/restic
# Generate a strong password and store it in your password manager FIRST.
openssl rand -base64 32 > ~/.config/restic/password
chmod 600 ~/.config/restic/password

cat > ~/.config/restic/env <<'EOF'
export RESTIC_REPOSITORY=/run/media/YOUR_USER/YOUR_DRIVE/restic-repo
export RESTIC_PASSWORD_FILE=$HOME/.config/restic/password
EOF
chmod 600 ~/.config/restic/env

. ~/.config/restic/env
restic init
```

**If you lose the password, the backups are unrecoverable.** Keep a copy somewhere that isn't on this machine.

## 3. Exclusions

`~/.config/restic/excludes`:

```
/home/YOUR_USER/.cache
/home/YOUR_USER/.local/share/Trash
/home/YOUR_USER/.local/share/containers
/home/YOUR_USER/.var/app/*/cache
/home/YOUR_USER/.ollama
/home/YOUR_USER/Downloads/iso
```

Adjust to your layout. Check what would be included with `restic backup --dry-run -vv ~`.

## 4. First backup

```bash
install -m 755 scripts/restic-backup.sh ~/.local/bin/restic-backup.sh
~/.local/bin/restic-backup.sh backup
~/.local/bin/restic-backup.sh snapshots
```

The script keeps 7 daily, 4 weekly and 6 monthly snapshots and prunes the rest. If the repository path doesn't exist (drive unplugged), it exits quietly without error.

## 5. Schedule it (systemd user timer)

`~/.config/systemd/user/restic-backup.service`:

```ini
[Unit]
Description=Restic backup

[Service]
Type=oneshot
ExecStart=%h/.local/bin/restic-backup.sh backup
Nice=10
IOSchedulingClass=idle
```

`~/.config/systemd/user/restic-backup.timer`:

```ini
[Unit]
Description=Daily restic backup

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now restic-backup.timer
systemctl --user list-timers
journalctl --user -u restic-backup.service -e
```

`Persistent=true` runs a missed backup the next time the machine is on.

## 6. Test a restore (do this now, and every few months)

```bash
. ~/.config/restic/env
restic snapshots
restic restore latest --target /tmp/restore-test --include /home/YOUR_USER/Documents
diff -r ~/Documents /tmp/restore-test/home/YOUR_USER/Documents && echo "restore matches"
rm -rf /tmp/restore-test
restic check                      # repository integrity (add --read-data occasionally)
```

A backup you have never restored is a hope, not a backup.

## 7. Things restic won't save you from

- **LUKS header and keys.** Back up the header and store it offline:
  ```bash
  sudo cryptsetup luksHeaderBackup /dev/<luks-device> --header-backup-file luks-header.img
  ```
  Keep recovery passphrases in your password manager.
- **Package list:** `rpm -qa --qf '%{NAME}\n' | sort > ~/package-list.txt` (lands in your home, so it's backed up).
- **Flatpak list:** `flatpak list --app --columns=application > ~/flatpak-list.txt`
- **3-2-1 rule:** three copies, two media, one off-site. One external drive is a start. Add a cloud or second location for the rest.

## 8. Before big changes

Before a Fedora version upgrade, or before installing anything risky:

```bash
~/.local/bin/restic-backup.sh backup
sudo snapper -c root create -d "before upgrade"
```

## Troubleshooting

- **"Repository path not present":** the drive isn't mounted at the path in `env`. Mount paths under `/run/media` include your username and the volume label.
- **Timer didn't run:** `systemctl --user list-timers`, and check the journal. User timers run only while your user session is active unless you enable lingering (`loginctl enable-linger $USER`).
- **Backups are slow:** the first run is the slow one. Later runs only upload changes.
- **Out of space:** run `restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune`, or tighten the retention in the script.
