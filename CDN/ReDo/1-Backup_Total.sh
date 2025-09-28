#!/bin/bash
destiny=$(sed -n '2p' /srv/scripts/config/backupcont)
datetime=$(date +"%d_%m_%y")
# Apenas uma revalidação por segurança. Isso deveria ocorrer no LINITE mas alguns servidores não tem esse dado
# e ele não será coletado em sistemas virgens, a ausência de containers .tar.lz4 em /srv/containers vai impedir.
yamlbase="/srv/system.yaml"
CURRENT_MACHINE_ID=$(cat /etc/machine-id 2>/dev/null)
BACKUP_MACHINE_ID=$(yq -r '.Informacoes.machine_id' "$yamlbase" 2>/dev/null)
if [ "$CURRENT_MACHINE_ID" = "$BACKUP_MACHINE_ID" ]; then
  :;
else
  if [ -z "$BACKUP_MACHINE_ID" ] || [ "$BACKUP_MACHINE_ID" = "null" ]; then
    MACHINE_ID=$(cat /etc/machine-id)
    sudo yq -i ".Informacoes.machine_id = \"${MACHINE_ID}\"" "$yamlbase"
  fi
fi
# ETAPA 00
##########################################################################################################################
if [ -b "$(sudo blkid -L bkpsys 2>/dev/null)" ]; then
    :;
else
  mount_point=$(sed -n '2p' /srv/scripts/config/backupcont)
  device=$(df "$mount_point" | grep -v Filesystem | awk '{print $1}')
  [[ -n "$device" ]] && sudo e2label "$device" "bkpsys" || echo "Erro: dispositivo não encontrado"
fi
# ETAPA 01
##########################################################################################################################
sudo crontab -l | sudo tee "$destiny"/crontab-bkp > /dev/null
sudo cp -r /srv/scripts "$destiny"
sudo cp /srv/*.yaml "$destiny"
# ETAPA 02
##########################################################################################################################
sudo tar -I 'lz4 -1 -c -' -cpf "$destiny"/etc-"$datetime".tar.lz4 \
    --exclude='/etc/machine-id' \
    --exclude='/etc/fstab' \
    /etc/
sudo cp /etc/fstab "$destiny"/fstab.backup
# ETAPA 03
##########################################################################################################################
sudo mkdir -p "$destiny"/docker-network-backup
for network in $(docker network ls --format "{{.Name}}" | grep -v "bridge\|host\|none"); do
  docker network inspect "$network" | sudo tee "$destiny"/docker-network-backup/"$network".json> /dev/null
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
sudo find /var/lib/libvirt/images/ -iname "*pfsense*" -exec rsync -aHAXv --numeric-ids --sparse {} "$destiny"/ \;
virsh list --all --name | grep -i pfsense | while read -r vm_name; do
  if [[ -n "$vm_name" ]]; then
    virsh dumpxml "$vm_name" | sudo tee "$destiny"/"$vm_name"-vm.xml> /dev/null
    virsh start "$vm_name"
  fi
done
