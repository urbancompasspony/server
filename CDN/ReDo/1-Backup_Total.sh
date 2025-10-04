#!/bin/bash

destiny=$(sed -n '2p' /srv/scripts/config/backupcont)
datetime=$(date +"%d_%m_%y")
yamlbase="/srv/system.yaml"

CURRENT_MACHINE_ID=$(cat /etc/machine-id 2>/dev/null)
BACKUP_MACHINE_ID=$(yq -r '.Informacoes.machine_id' "$yamlbase" 2>/dev/null)

function etapa00 {
  if [ "$(hostname)" = "ubuntu-server" ]; then
    clear
    echo "Tentativa de criar um backup a partir de um sistema limpo."
    echo "Saindo..."
    sleep 3
    exit 1
  else
    if [ "$CURRENT_MACHINE_ID" = "$BACKUP_MACHINE_ID" ]; then
      :;
    else
      if [ -z "$BACKUP_MACHINE_ID" ] || [ "$BACKUP_MACHINE_ID" = "null" ]; then
        MACHINE_ID=$(cat /etc/machine-id)
        sudo yq -i ".Informacoes.machine_id = \"${MACHINE_ID}\"" "$yamlbase"
      fi
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
  # Desliga todas as VMs pfsense que estão rodando
  virsh list --all --name | grep -i pfsense | while read -r vm_name; do
    if [[ -n "$vm_name" ]] && virsh list --state-running --name | grep -q "^$vm_name$"; then
        echo "🔄 Desligando $vm_name"
        virsh shutdown "$vm_name"
        wait_vm_shutdown "$vm_name"
    fi
  done
  
  # Backup dos discos das VMs pfsense usando domblklist
  echo "💾 Iniciando backup dos discos..."
  virsh list --all --name | grep -i pfsense | while read -r vm_name; do
    if [[ -n "$vm_name" ]]; then
      echo "📦 Processando VM: $vm_name"
      # Pega apenas os discos reais (type=disk, device=file)
      virsh domblklist "$vm_name" --details | awk '/^file.*disk/ {print $4}' | while read -r disk_path; do
        if [[ -n "$disk_path" && -f "$disk_path" ]]; then
          echo "  └─ Copiando: $(basename "$disk_path")"
          sudo rsync -aHAXv --numeric-ids --sparse "$disk_path" "$destiny"/
        fi
      done
    fi
  done
  
  # Exporta XMLs e reinicia as VMs
  echo "📄 Exportando configurações..."
  virsh list --all --name | grep -i pfsense | while read -r vm_name; do
    if [[ -n "$vm_name" ]]; then
      virsh dumpxml "$vm_name" | sudo tee "$destiny"/"$vm_name"-vm.xml > /dev/null
      echo "🔃 Reiniciando $vm_name"
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
          echo "⚠️ Timeout atingido - forçando desligamento de $vm_name"
          virsh destroy "$vm_name"
          sleep 10
          break
      fi
      
      if [ $((count % 30)) -eq 0 ] && [ $count -gt 0 ]; then
          echo "⏳ Aguardando shutdown de $vm_name... (${count}s/${timeout}s)"
      fi
      
      sleep 2
      ((count+=2))
  done
  
  sync
  sleep 3
  
  echo "✅ VM $vm_name parada"
}

etapa00
etapa01
etapa02
etapa03
etapa04
etapa05
exit 0
