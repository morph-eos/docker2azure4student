#!/usr/bin/env bash
# Idempotent host preparation, run on the VM over SSH before the container
# starts (`ssh user@vm 'sudo bash -s' < scripts/vm-prepare-host.sh`).
#
# - Swap file: the B-series VM has under 1 GiB of RAM and ships without swap,
#   so a memory spike goes straight to the kernel OOM killer.
# - Persistent journald: containers run with the journald log driver, so their
#   logs outlive `docker rm` on every deploy. Size is capped so the disk cannot
#   fill.
set -euo pipefail

SWAP_FILE="${SWAP_FILE:-/swapfile}"
SWAP_SIZE_MB="${SWAP_SIZE_MB:-2048}"
SWAPPINESS="${SWAPPINESS:-10}"
JOURNAL_MAX_USE="${JOURNAL_MAX_USE:-300M}"

if ! swapon --show=NAME --noheadings | grep -qx "$SWAP_FILE"; then
  if [ ! -f "$SWAP_FILE" ]; then
    # dd, not fallocate: swapon rejects files with holes on some filesystems.
    dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE_MB" status=none
    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE" >/dev/null
  fi
  swapon "$SWAP_FILE"
fi
grep -qs "^$SWAP_FILE " /etc/fstab || echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab

echo "vm.swappiness=$SWAPPINESS" > /etc/sysctl.d/99-locus-swap.conf
sysctl -q -w "vm.swappiness=$SWAPPINESS"

mkdir -p /var/log/journal /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-locus.conf <<CONF
[Journal]
Storage=persistent
SystemMaxUse=$JOURNAL_MAX_USE
CONF
systemctl restart systemd-journald

echo "swap:"; swapon --show
free -m
journalctl --disk-usage
