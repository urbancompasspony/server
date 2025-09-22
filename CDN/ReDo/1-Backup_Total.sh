#!/bin/bash

destiny=$(sed -n '2p' /srv/scripts/config/backupcont)
datetime=$(date +"%d_%m_%y")
sudo tar -I 'lz4 -1 -c -' -cpf "$destiny"/etc-"$datetime".tar.lz4 \
    --exclude='/etc/machine-id' \
    --exclude='/etc/fstab' \
    /etc/

sudo cp /etc/fstab "$destiny"/fstab-"$datetime".backup

mkdir -p docker-network-backup
for network in $(docker network ls --format "{{.Name}}" | grep -v "bridge\|host\|none"); do
    docker network inspect $network > docker-network-backup/$network.json
done

# 1. Exportar configuração da VM
datetime=$(date +%Y%m%d_%H%M%S)
virsh dumpxml pfsense > /mnt/disk01/pfsense-vm-$datetime.xml
# 2. Parar a VM (recomendado para consistência)
virsh shutdown pfsense
# 3. Copiar o arquivo qcow2
sudo rsync -a /var/lib/libvirt/images/pfsense*.qcow2 /mnt/disk01/pfsense-backup.qcow2
# 4. Religar a VM
virsh start pfsense
