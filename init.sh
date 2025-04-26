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
    [ -b "$disk_device" ] && break
    echo "[WAIT] Waiting for disk $disk_device..."
    sleep 2
done
[ -b "$disk_device" ] || { echo "[ERROR] Disk $disk_device not detected after 60s."; exit 1; }

# Create ZFS pool and dataset
if ! zpool list | grep -q "$zpool_name"; then
    echo "[INFO] Creating ZFS pool $zpool_name..."
    zpool create -f "$zpool_name" "$disk_device"
fi

echo "[INFO] Creating ZFS dataset $zfs_dataset..."
zfs create -o mountpoint="$zfs_mountpoint" "$zfs_dataset" 2>/dev/null || true

# Set permissions
echo "[INFO] Setting permissions for $zfs_mountpoint..."
chmod 777 "$zfs_mountpoint"

# Configure NFS export
echo "[INFO] Configuring NFS export for $zfs_mountpoint..."
grep -q "$zfs_mountpoint" /etc/exports || echo "$zfs_mountpoint *(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
exportfs -ra

# Enable and restart services
echo "[INFO] Starting SSH and NFS services..."
systemctl enable ssh
systemctl restart ssh
systemctl enable nfs-server
systemctl restart nfs-server

echo "[SUCCESS] ZFS pool, NFS share, and SSH access are ready"
echo "[INFO] NFS share available at: $zfs_mountpoint"
echo "[INFO] SSH access available at port 22 for user 'root'"
