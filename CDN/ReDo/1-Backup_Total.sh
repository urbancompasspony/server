#!/bin/bash
destiny=$(sed -n '2p' /srv/scripts/config/backupcont)
datetime=$(date +"%d_%m_%y")
# ETAPA 01
##########################################################################################################################
if [ -b "$(sudo blkid -L bkpsys 2>/dev/null)" ]; then
    :;
else
  mount_point=$(sed -n '2p' /srv/scripts/config/backupcont)
  device=$(df "$mount_point" | grep -v Filesystem | awk '{print $1}')
  [[ -n "$device" ]] && sudo e2label "$device" "bkpsys" || echo "Erro: dispositivo não encontrado"
fi
# ETAPA 02
##########################################################################################################################
sudo tar -I 'lz4 -1 -c -' -cpf "$destiny"/etc-"$datetime".tar.lz4 \
    --exclude='/etc/machine-id' \
    --exclude='/etc/fstab' \
    /etc/
sudo cp /etc/fstab "$destiny"/fstab-"$datetime".backup
sudo cp /srv/*.yaml "$destiny"/
# ETAPA 03
##########################################################################################################################
mkdir -p "$destiny"/docker-network-backup
for network in $(docker network ls --format "{{.Name}}" | grep -v "bridge\|host\|none"); do
  docker network inspect "$network" > "$destiny"/docker-network-backup/"$network".json
done
# ETAPA 04
##########################################################################################################################
# Função para aguardar VM pfSense existente parar
wait_vm_shutdown() {
    local vm_name="$1"
    local timeout=180
    local count=0
    while virsh list --state-running --name | grep -q "^$vm_name$"; do
        if [ $count -ge $timeout ]; then
            virsh destroy "$vm_name"
            sleep 2
            break
        fi
        sleep 2
        ((count+=2))
    done
    echo "VM $vm_name parada"
}
virsh list --all --name | grep -i pfsense | while read -r vm_name; do
    if [[ -n "$vm_name" ]] && virsh list --state-running --name | grep -q "^$vm_name$"; then
        virsh shutdown "$vm_name"
        wait_vm_shutdown "$vm_name"
    fi
done
sudo find /var/lib/libvirt/images/ -iname "*pfsense*" -exec rsync -va {} "$destiny"/ \;
virsh list --all --name | grep -i pfsense | while read -r vm_name; do
    if [[ -n "$vm_name" ]]; then
        virsh dumpxml "$vm_name" > "$destiny"/"$vm_name"-vm-"$datetime".xml
        virsh start "$vm_name"
    fi
done
