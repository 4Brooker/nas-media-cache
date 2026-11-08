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
```

Passing a file instead of a folder prefetches the folder it is in. When started outside a terminal (e.g. from a viewer's menu) it shows a progress window automatically. Cancelling the window asks for confirmation first, with "Keep running" as the default.

Prefetching costs as much time and data as viewing the files once, so on a slow link use `-i` or `-n` for large video folders.

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
