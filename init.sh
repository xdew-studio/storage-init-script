#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/zfs-nfs-storage-init.log | logger -t zfs-nfs-init -s) 2>&1

echo "[INFO] Installing ZFS, NFS server and SSH..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y zfsutils-linux nfs-kernel-server openssh-server curl ca-certificates file

# Variables
zpool_name="tank"
zfs_dataset="tank/k8s"
zfs_mountpoint="/mnt/tank/k8s"
disk_device="/dev/sdb"

# Wait for disk
echo "[INFO] Waiting for the disk $disk_device to appear..."
for i in {1..30}; do
    if [ -b "$disk_device" ]; then
        break
    fi
    echo "[WAIT] Waiting for disk $disk_device..."
    sleep 2
done
if [ ! -b "$disk_device" ]; then
    echo "[ERROR] Disk $disk_device not detected after 60 seconds."
    exit 1
fi

# Wipe any existing filesystem signatures
echo "[INFO] Wiping existing filesystem signatures on $disk_device..."
wipefs -a "$disk_device" || true

# Extra safety: zero the first and last 100MB
echo "[INFO] Zeroing first and last 100MB of $disk_device to clear old metadata..."
dd if=/dev/zero of="$disk_device" bs=1M count=100 status=progress || true
dd if=/dev/zero of="$disk_device" bs=1M seek=$(( $(blockdev --getsz "$disk_device") / 2048 - 100 )) count=100 status=progress || true

# Force kernel to reread partition table
partprobe "$disk_device" || true
sleep 2

# Create ZFS pool and dataset
if ! zpool list | grep -q "^$zpool_name"; then
    echo "[INFO] Creating ZFS pool $zpool_name..."
    zpool create -f "$zpool_name" "$disk_device"
else
    echo "[INFO] ZFS pool $zpool_name already exists."
fi

if ! zfs list | grep -q "^$zfs_dataset"; then
    echo "[INFO] Creating ZFS dataset $zfs_dataset..."
    zfs create -o mountpoint="$zfs_mountpoint" "$zfs_dataset"
else
    echo "[INFO] ZFS dataset $zfs_dataset already exists."
fi

# Set permissions
echo "[INFO] Setting permissions for $zfs_mountpoint..."
chmod 777 "$zfs_mountpoint"

# Configure NFS export
echo "[INFO] Configuring NFS export for $zfs_mountpoint..."
if ! grep -q "$zfs_mountpoint" /etc/exports; then
    echo "$zfs_mountpoint *(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
    exportfs -ra
else
    echo "[INFO] NFS export for $zfs_mountpoint already configured."
fi

# Enable and restart services
echo "[INFO] Starting SSH and NFS services..."
systemctl enable --now ssh
systemctl enable --now nfs-server

echo "[SUCCESS] ZFS pool, NFS share, and SSH access are ready"
echo "[INFO] NFS share available at: $zfs_mountpoint"
echo "[INFO] SSH access available at port 22 for user 'root'"
