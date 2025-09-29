#!/bin/bash
destiny=$(sed -n '2p' /srv/scripts/config/backupcont)
datetime=$(date +"%d_%m_%y")
yamlbase="/srv/system.yaml"

CURRENT_MACHINE_ID=$(cat /etc/machine-id 2>/dev/null)
BACKUP_MACHINE_ID=$(yq -r '.Informacoes.machine_id' "$yamlbase" 2>/dev/null)

function etapaX {
  if [ "$(hostname)" = "ubuntu-server" ]; then
    clear
    echo "Tentativa de criar um backup a partir de um sistema limpo."
    echo "Saindo..."
    sleep 3
    exit 1
  fi
}

function etapa00 {
  if [ "$CURRENT_MACHINE_ID" = "$BACKUP_MACHINE_ID" ]; then
    :;
  else
    if [ -z "$BACKUP_MACHINE_ID" ] || [ "$BACKUP_MACHINE_ID" = "null" ]; then
      MACHINE_ID=$(cat /etc/machine-id)
      sudo yq -i ".Informacoes.machine_id = \"${MACHINE_ID}\"" "$yamlbase"
    fi
  fi
}

function etapa01 {
  if [ -b "$(sudo blkid -L bkpsys 2>/dev/null)" ]; then
      :;
  else
    mount_point=$(sed -n '2p' /srv/scripts/config/backupcont)
    device=$(df "$mount_point" | grep -v Filesystem | awk '{print $1}')
    [[ -n "$device" ]] && sudo e2label "$device" "bkpsys" || echo "Erro: dispositivo não encontrado"
  fi
}

function etapa02 {
  sudo crontab -l | sudo tee "$destiny"/crontab-bkp > /dev/null
  sudo cp -r /srv/scripts "$destiny"
  sudo cp /srv/*.yaml "$destiny"
}

function etapa03 {
  sudo tar -I 'lz4 -1 -c -' -cpf "$destiny"/etc-"$datetime".tar.lz4 \
    --exclude='/etc/machine-id' \
    --exclude='/etc/fstab' \
    /etc/
  sudo cp /etc/fstab "$destiny"/fstab.backup
}

function etapa04 {
  sudo mkdir -p "$destiny"/docker-network-backup
  for network in $(docker network ls --format "{{.Name}}" | grep -v "bridge\|host\|none"); do
    docker network inspect "$network" | sudo tee "$destiny"/docker-network-backup/"$network".json> /dev/null
  done
}

function etapa05 {
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
}

function wait_vm_shutdown {
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

etapaX
etapa00
etapa01
etapa02
etapa03
etapa04
etapa05
exit 0
