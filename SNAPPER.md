# Automatic Btrfs Snapshots (openSUSE-style) on Fedora

Fedora can match most of openSUSE's snapper setup: hourly timeline snapshots, automatic cleanup, and pre/post snapshots around package transactions. Booting into a snapshot and rolling back is **not** equivalent. This guide is from web research (Fedora forum threads, community guides, the `libdnf5-actions` man page) and general knowledge. **Nothing here was tested on Fedora 45.** Scripts were syntax-checked only.

Scripts: [`scripts/snapper-setup.sh`](scripts/snapper-setup.sh), [`scripts/dnf-snap`](scripts/dnf-snap)

> Snapshots live on the same disk. They undo a bad update. They do **not** protect against disk failure or deletion of the whole filesystem. Keep real backups too: [BACKUP.md](BACKUP.md).

## What you get vs openSUSE

| Feature | openSUSE | Fedora |
|---|---|---|
| Hourly timeline snapshots and cleanup | Yes | Yes, via snapper timers |
| Pre/post snapshot on every package transaction | `snapper-zypp-plugin` | dnf5 Actions plugin, or the `dnf-snap` wrapper |
| Boot a snapshot from GRUB | Built in | `grub-btrfs`, which may need building from source |
| One-command permanent rollback | `snapper rollback` | Possible but layout-dependent. Test it first |
| `/boot` covered | Yes | No (separate partition) |

## 1. Check your layout

```bash
./scripts/snapper-setup.sh check
```

It's read-only. It confirms root is Btrfs, lists subvolumes and shows any existing snapper config.

## 2. Timeline and cleanup

```bash
./scripts/snapper-setup.sh timers
```

This installs snapper if needed, creates the `root` config, sets limits, enables `snapper-timeline.timer` and `snapper-cleanup.timer`, and takes a baseline snapshot.

Default limits (edit in `/etc/snapper/configs/root`):

| Setting | Value |
|---|---|
| Hourly | 5 |
| Daily | 7 |
| Weekly, monthly, yearly | 0 |
| Pre/post pairs kept (`NUMBER_LIMIT`) | 10 |

Check:

```bash
snapper -c root list
systemctl list-timers | grep snapper
```

To snapshot `/home` as well (separate config):

```bash
./scripts/snapper-setup.sh home
```

## 3. Keep big, fast-changing data out of your snapshots

Snapshots keep old versions of changed blocks. VM disks, container images and model files change constantly and will eat your disk. **Snapper does not snapshot nested subvolumes**, so give those directories their own subvolume:

```bash
# Shut down ALL VMs first.
./scripts/snapper-setup.sh subvol /var/lib/libvirt/images nocow
```

What it does: moves the directory aside, creates a subvolume in its place, disables copy-on-write for new files (`nocow`, recommended for VM disks), copies the data back, restores SELinux labels, and leaves `images.old` for you to delete after you verify. It refuses to run while VMs are running and asks for confirmation.

Caveats:

- **Back up first.** It moves your data. You need free space about the size of the directory.
- `nocow` disables checksums and compression for those files.
- Do the same for other large, volatile data you don't need to roll back (for example `/var/lib/ollama` if you used the native Ollama install, or `~/.ollama`). Use the same command without `nocow`.
- Do this **before** you fill the directory, if you can. It's much easier on an empty install.

## 4. Pre/post snapshots around dnf

Fedora's dnf5 dropped the old snapper plugin. There are two options.

### Option A: dnf5 Actions plugin (automatic)

```bash
./scripts/snapper-setup.sh actions
```

It installs `libdnf5-plugin-actions` and writes `/etc/dnf/libdnf5-plugins/actions.d/snapper.actions`: a `pre_transaction` rule that creates a pre snapshot and remembers its number, and a `post_transaction` rule that creates the matching post snapshot.

The rule syntax has changed between versions, so **verify it against `man libdnf5-actions` on your system**. Then test:

```bash
sudo dnf install -y cowsay
snapper -c root list          # expect a new pre/post pair
sudo dnf remove -y cowsay
```

Known gap: snapshot descriptions say `dnf-transaction`, not which packages changed. A forum reply suggests adding the package name variable (`${pkg.nevra}`) to the description. I haven't verified that.

### Option B: wrapper script (reliable fallback)

If the Actions rule doesn't behave, use the wrapper. It takes a pre snapshot, runs dnf, then the matching post snapshot, and puts the command in the description.

```bash
install -m 755 scripts/dnf-snap ~/.local/bin/dnf-snap
dnf-snap upgrade
dnf-snap install some-package
```

Read-only commands (`search`, `info`, `list`) pass straight through. You can add `alias dnf='dnf-snap'` to your shell profile. It only wraps when you use it, so GUI updaters (GNOME Software) bypass it. Use **either** Option A or B, not both, or you'll get double snapshots.

## 5. Rolling back

**Undo specific changes** (safest, no reboot into an old root):

```bash
snapper -c root list
snapper -c root status 12..13           # what changed between pre #12 and post #13
snapper -c root undochange 12..13       # revert those changes
```

**Browse and restore a few files:** snapshots are mounted read-only under `/.snapshots/<number>/snapshot/`.

**Full rollback / boot into a snapshot:**

- **grub-btrfs** adds snapshots to the GRUB menu. Check whether your Fedora release packages it. Guides mention building it from source. Booting a snapshot there is a **preview only**.
- A permanent rollback needs a separate step (`snapper rollback`, or the Btrfs Assistant GUI's Restore), then a reboot. Fedora's layout differs from openSUSE's, so behavior is layout-dependent.
- **Test a rollback now, while the system is healthy.** Create a marker file, take a snapshot, delete the file, roll back, and confirm the file returns. Don't find out that it doesn't work during an emergency.
- Rescue plan if the system won't boot: boot a Fedora live USB, mount the Btrfs volume, and restore from a snapshot manually. Know this path before you need it.

## 6. Day-to-day

```bash
snapper -c root list                    # snapshots
sudo snapper -c root create -d "before experiment"
sudo snapper -c root delete 15          # remove one
sudo btrfs filesystem usage /           # space
sudo btrfs filesystem du -s /.snapshots # snapshot space use
```

**Btrfs Assistant** (`btrfs-assistant`, GUI) lists, creates, deletes and restores snapshots and can manage the snapper config.

## 7. Troubleshooting

- **Disk filling up:** large VM disks or container images in snapshotted subvolumes. Move them to their own subvolumes (step 3), then delete old snapshots.
- **No snapshots appear on a timer:** `systemctl status snapper-timeline.timer`, and `journalctl -u snapper-timeline.service`.
- **Cleanup never deletes:** check `TIMELINE_CLEANUP=yes` and `NUMBER_CLEANUP=yes` in the config, and that `snapper-cleanup.timer` is enabled.
- **dnf Actions rule does nothing:** check the file name ends in `.actions`, check `man libdnf5-actions` for the syntax, and check `dnf5 --version`. Fall back to `dnf-snap`.
- **`snapper create-config` fails:** a `.snapshots` subvolume or config may already exist. Run `snapper list-configs`.
- **Rollback didn't boot:** boot a live USB and restore manually. This is why you test early and keep backups.

## Sources

- [Fedora Discussion: Getting snapper/btrfs-assistant to work with dnf5](https://discussion.fedoraproject.org/t/getting-snapper-btrfs-assistant-to-work-with-dnf5/133948)
- [libdnf5-actions man page](https://www.mankier.com/8/libdnf5-actions)
- [ComputingForGeeks: Btrfs snapshots, Snapper and automatic rollback on Fedora and openSUSE](https://computingforgeeks.com/btrfs-snapshots-snapper-automatic-rollback-fedora-opensuse/)
- [ComputingForGeeks: Btrfs, Snapper and grub-btrfs on Fedora](https://computingforgeeks.com/btrfs-snapper-grub-btrfs-fedora/)
- [Fedora Discussion: BTRFS snapshots in Fedora, step-by-step guide](https://discussion.fedoraproject.org/t/btrfs-snapshots-in-fedora-the-definitive-step-by-step-easy-and-safe-guide/194483)
