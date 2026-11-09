# nas-media-cache

Fast photo and video previews from a NAS over a slow or high-latency link (e.g. NFS over Tailscale/VPN), on Linux.

Viewers like XnView MP only preload the next image in memory, so every photo or video on a remote NFS share is fetched over the network again each time you open it. This project adds a buffer underneath:

- **Local disk cache (FS-Cache)**: every file read from the NAS is kept on your local disk. Opening it again is instant, even after a reboot.
- **16 MB read-ahead**: videos and large photos are fetched ahead of where you are, like a streaming buffer (the kernel default is 128 KB).
- **Attribute caching**: folder listings are cached for 60 seconds, so browsing feels faster.
- **`nas-prefetch`**: load a whole folder into the cache in advance, with a progress window, so the first view is fast too.

It works below the viewer, so it helps XnView MP, file managers, video players and anything else that reads from the mount.

## Requirements

- Debian/Ubuntu-based Linux (the setup script uses `apt`)
- The NAS mounted over NFS, with an entry in `/etc/fstab`
- `zenity` for the progress window (preinstalled on most desktops)
- `python3` (preinstalled on Debian/Ubuntu/Mint)

## Install

```bash
git clone https://github.com/4Brooker/nas-media-cache.git
cd nas-media-cache

# One-time setup of the cache for your NFS mount (close viewers/file managers using it first)
sudo ./nas-cache-setup.sh /mnt/nas

# Install the prefetch command
cp nas-prefetch ~/.local/bin/
```

`nas-cache-setup.sh`:

1. installs and starts `cachefilesd` (cache in `/var/cache/fscache`)
2. adds `fsc,actimeo=60` to the mount's options in `/etc/fstab` (backup: `/etc/fstab.bak-nas-cache`)
3. adds a udev rule that sets 16 MB read-ahead on NFS mounts
4. remounts the share and prints the result

Check that the cache is filling after browsing some files:

```bash
sudo du -sh /var/cache/fscache
```

## Prefetching folders

```bash
nas-prefetch /mnt/nas/Photos/2025          # one folder
nas-prefetch -r /mnt/nas/Photos/2025       # including subfolders
nas-prefetch -i /mnt/nas/Photos/2025       # photos only, skip videos
nas-prefetch -n 50 /mnt/nas/Photos/2025    # only the first 50 files
nas-prefetch -g /mnt/nas/Photos/2025       # progress window instead of terminal output
nas-prefetch -b 50% /mnt/nas/Photos/2025   # use at most half of the available bandwidth
nas-prefetch -b 5M /mnt/nas/Photos/2025    # at most 5 MiB/s (also: 40Mbit, 500K, off)
```

Passing a file instead of a folder prefetches the folder it is in. When started outside a terminal (e.g. from a viewer's menu) it shows a progress window automatically. The window shows which folder is being fetched (useful with `-r`), the number of files and data done, the speed and the time left.

**Pause** freezes the prefetch and asks whether to resume or stop, with "Resume" as the default. Closing the window does the same. Files loaded so far stay cached either way, and time spent paused does not count towards the speed or time-left estimate. With a percentage limit, Resume measures the maximum speed again, since the network may have changed while the prefetch was paused. In a terminal, pause with Ctrl+Z and continue with `fg`.

Prefetching costs as much time and data as viewing the files once, so on a slow link use `-i` or `-n` for large video folders.

### Bandwidth limit

By default prefetching uses at most 50% of the measured maximum speed, to leave room for other traffic (video calls, streaming, other people on the network). Use `-b off` for full speed, or set a different limit:

- **A fixed rate**, e.g. `5M` (MiB/s), `500K` or `40Mbit`.
- **A percentage**, e.g. `50%`. Prefetching first runs at full speed for 15 seconds or 10 files, whichever comes first, to measure the maximum speed. After that it is limited to that percentage of the measurement. The speed is measured from the NFS mount's network counter, so files that are already cached don't inflate it. If less than 1 MiB came over the network, the measurement starts over.

The limit covers all files read at the same time together. The progress window shows the active limit. Measurements count other traffic on the same NAS mount too, such as browsing photos while it measures.

### Settings

Defaults go in `~/.config/nas-prefetch.conf`. This is useful when prefetch is started from XnView, where you can't pass options. Command-line options override the file.

```bash
BANDWIDTH=50%       # off, a percentage, or a fixed rate like 5M or 40Mbit
MEASURE_SECONDS=15  # percentage limit: measure the maximum speed for this many seconds...
MEASURE_FILES=10    # ...or this many files, whichever comes first
PARALLEL=4          # files read at the same time
```

### XnView MP integration

1. Right-click any photo → **Open with → Configure programs...**
2. Add a program named `Prefetch folder` with path `/home/<you>/.local/bin/nas-prefetch`

Right-clicking a photo → **Open with → Prefetch folder** now loads its whole folder into the cache.

## How the cache behaves

- **Cached files are not removed when you prefetch more.** The cache keeps everything until free disk space drops below 7%. It then removes the least recently used files until 10% is free, and stops caching at 3% free. Thresholds are set in `/etc/cachefilesd.conf`.
- **Edits go straight to the NAS.** The cache only speeds up reads. Saved files are written to the NAS, and stale cached copies are discarded.
- **Changes from other devices** can take up to 60 seconds to show up, because of the attribute caching.
- **Suspend is fine**: a running prefetch freezes and continues after resume. After a reboot, run it again. Files already cached are skipped through in seconds.

## Undo

```bash
sudo cp /etc/fstab.bak-nas-cache /etc/fstab
sudo rm /etc/udev/rules.d/99-nfs-readahead.rules
sudo apt remove cachefilesd
```

Then remount the share or reboot.

## License

MIT
