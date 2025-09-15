
sudo mkdir -p /mnt/bkpsys

Encontrar o bkpsys
lsblk -f | grep bkpsys
findfs LABEL=bkpsys
blkid | grep bkpsys

Montar bkpsys
sudo mount LABEL="bkpsys" "$MOUNT_POINT"

Restaurar arquivos .yaml para seus devidos lugares.
FSTAB: LABEL=sysbkp    /mnt/sysbkp    ext4    defaults,noauto    0 2

Encontrar todos os containers recentes:
find /mnt/dados/BACKUP_CONTAINERS/ -type f -name "*.tar.lz4" -mtime -1 -ls


sudo mkdir -p /srv/containers
find /mnt/dados/BACKUP_CONTAINERS/ -type f -name "*.tar.lz4" -mtime -1 -print0 | \
while IFS= read -r -d '' file; do
    echo "Restaurando: $file"
    sudo tar -I 'lz4 -d -c -' -xf "$file" -C "$DESTINO"
    echo "Concluído: $(basename "$file")"
done


# 1. Parar VM se estiver rodando
virsh destroy pfsense
# 2. Remover VM atual
virsh undefine pfsense
# 3. Restaurar arquivo qcow2
cp /backup/pfsense-backup.qcow2 /var/lib/libvirt/images/pfsense.qcow2
# 4. Redefinir VM
virsh define pfsense-backup.xml
# 5. Iniciar VM
virsh start pfsense
