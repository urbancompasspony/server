#!/bin/bash
destiny=$(sed -n '1p' /srv/scripts/config/backupvm)

function check_destination {
  # Extrai o ponto de montagem real do caminho
  mount_point=$(df "$destiny" 2>/dev/null | awk 'NR==2 {print $6}')
  
  if [[ -z "$mount_point" ]]; then
    echo "ERRO: Não foi possível determinar o ponto de montagem de $destiny" >&2
    return 1
  fi
  
  if ! mountpoint -q "$mount_point"; then
    echo "ERRO: $mount_point não está montado" >&2
    return 1
  fi
  
  if ! sudo mkdir -p "$destiny"; then
    echo "ERRO: Não foi possível criar $destiny" >&2
    return 1
  fi
  
  available_space=$(df -BG "$destiny" | awk 'NR==2 {print $4}' | sed 's/G//')
  if [ "$available_space" -lt 50 ]; then
    echo "AVISO: Apenas ${available_space}GB disponíveis em $destiny" >&2
  fi
  
  return 0
}

function backup_vm {
  if ! check_destination; then
    exit 1
  fi
  
  # Desliga VMs em execução (exceto pfsense)
  virsh list --all --name | grep -v -i pfsense | grep -v '^$' | while read -r vm_name; do
    if [[ -n "$vm_name" ]] && virsh list --state-running --name | grep -q "^$vm_name$"; then
        virsh shutdown "$vm_name" --mode acpi 2>/dev/null
        wait_vm_shutdown "$vm_name"
    fi
  done
  
  # Backup dos discos
  virsh list --all --name | grep -v -i pfsense | grep -v '^$' | while read -r vm_name; do
    if [[ -n "$vm_name" ]]; then
      virsh domblklist "$vm_name" --details | awk '/^file.*disk/ {print $4}' | while read -r disk_path; do
        if [[ -n "$disk_path" && -f "$disk_path" ]]; then
          sudo rsync -aHAX --numeric-ids --sparse "$disk_path" "$destiny"/ 2>&1 | grep -E "^(ERRO|ERROR|failed)"
        fi
      done
    fi
  done
  
  # Backup dos XMLs e restart
  virsh list --all --name | grep -v -i pfsense | grep -v '^$' | while read -r vm_name; do
    if [[ -n "$vm_name" ]]; then
      virsh dumpxml "$vm_name" | sudo tee "$destiny"/"$vm_name"-vm.xml > /dev/null 2>&1
      
      if virsh list --state-shutoff --name | grep -q "^$vm_name$"; then
        virsh start "$vm_name" >/dev/null 2>&1
      fi
    fi
  done
  
  echo "Backup concluído: $destiny"
}

function wait_vm_shutdown {
  local vm_name="$1"
  local timeout=270
  local count=0
  
  while virsh list --state-running --name | grep -q "^$vm_name$"; do
      if [ $count -ge $timeout ]; then
          echo "TIMEOUT: Forçando desligamento de $vm_name" >&2
          virsh destroy "$vm_name" 2>/dev/null
          sleep 10
          break
      fi
      
      sleep 2
      ((count+=2))
  done
  
  sync
  sleep 3
}

backup_vm
exit 0
