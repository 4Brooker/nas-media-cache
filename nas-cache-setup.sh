#!/usr/bin/env bash
# One-time setup to make browsing/previewing photos and videos on an NFS (NAS) mount fast:
#  1. FS-Cache: files read once are kept on local disk, so re-opening is instant
#  2. 16 MB read-ahead on NFS mounts: videos/large photos stream with a buffer
#  3. 60 s attribute caching: faster folder listings
#
# Usage: sudo ./nas-cache-setup.sh MOUNTPOINT      (e.g. /mnt/nas, must be in /etc/fstab)
# For Debian/Ubuntu-based systems (uses apt).
set -euo pipefail

READAHEAD_KB=16384
EXTRA_OPTS=fsc,actimeo=60

mnt=${1:-}
[[ -n $mnt ]] || { sed -n '7p' "$0"; exit 1; }
mnt=${mnt%/}
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }

entry=$(awk -v m="$mnt" '$1 !~ /^#/ && $2 == m' /etc/fstab)
[[ -n $entry ]] || { echo "No /etc/fstab entry for $mnt"; exit 1; }
[[ $(awk '{print $3}' <<<"$entry") == nfs* ]] || { echo "$mnt is not an NFS mount in /etc/fstab"; exit 1; }

echo "== Installing cachefilesd (local disk cache for NFS)"
apt-get install -y cachefilesd
[[ -f /etc/default/cachefilesd ]] && sed -i 's/^#\?RUN=.*/RUN=yes/' /etc/default/cachefilesd
systemctl enable cachefilesd && systemctl restart cachefilesd

echo "== Adding $EXTRA_OPTS to $mnt in /etc/fstab (backup: /etc/fstab.bak-nas-cache)"
cp -n /etc/fstab /etc/fstab.bak-nas-cache
tmp=$(mktemp)
awk -v m="$mnt" -v extra="$EXTRA_OPTS" '
  $1 !~ /^#/ && $2 == m {
    n = split(extra, add, ",")
    for (i = 1; i <= n; i++) {
      key = add[i]; sub(/=.*/, "", key)
      if (("," $4 ",") !~ ("," key "[,=]")) $4 = $4 "," add[i]
    }
  }
  { print }' /etc/fstab > "$tmp"
cat "$tmp" > /etc/fstab
rm -f "$tmp"
awk -v m="$mnt" '$1 !~ /^#/ && $2 == m' /etc/fstab

echo "== Adding udev rule for ${READAHEAD_KB} KB NFS read-ahead (default is 128 KB)"
cat > /etc/udev/rules.d/99-nfs-readahead.rules <<EOF
SUBSYSTEM=="bdi", ACTION=="add", PROGRAM="/usr/bin/awk -v bdi=\$kernel 'BEGIN{ret=1} {if (\$4 == bdi) {ret=0}} END{exit ret}' /proc/fs/nfsfs/volumes", ATTR{read_ahead_kb}="$READAHEAD_KB"
EOF
udevadm control --reload

echo "== Remounting $mnt"
systemctl daemon-reload
if mountpoint -q "$mnt" && ! umount "$mnt" 2>/dev/null; then
  echo "!! $mnt is busy (close file managers/viewers) — changes apply after reboot."
  exit 0
fi
if [[ $entry == *x-systemd.automount* ]]; then
  systemctl restart "$(systemd-escape -p --suffix=automount "$mnt")"
else
  mount "$mnt"
fi
ls "$mnt" >/dev/null

echo "== Result"
findmnt -no FSTYPE,OPTIONS -T "$mnt" | grep '^nfs'
dev=$(awk -v m="$mnt" '$5 == m && $9 ~ /^nfs/ {print $3}' /proc/self/mountinfo | tail -1)
echo "read_ahead_kb: $(cat "/sys/class/bdi/$dev/read_ahead_kb")"
echo "cachefilesd: $(systemctl is-active cachefilesd)"
