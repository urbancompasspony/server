#!/bin/bash

# Lê o diretório de backup
backup_dir=$(sed -n '1p' /srv/scripts/config/backupvm)

if [ -z "$backup_dir" ]; then
  echo "ERRO: Caminho de backup vazio em /srv/scripts/config/backupvm" >&2
  exit 1
fi

if [ ! -d "$backup_dir" ]; then
  echo "ERRO: Diretório de backup não existe: $backup_dir" >&2
  exit 1
fi

# Procura todos os XMLs de VMs no backup
xml_files=$(find "$backup_dir" -maxdepth 1 -type f -name "*-vm.xml")

if [ -z "$xml_files" ]; then
  echo "ERRO: Nenhum XML de VM encontrado em $backup_dir" >&2
  exit 1
fi

# Restaura cada VM encontrada
echo "$xml_files" | while read -r xml_file; do
  vm_name=$(basename "$xml_file" | sed 's/-vm\.xml$//')
  
  echo "Restaurando VM: $vm_name"
  
  # Extrai os caminhos originais dos discos do XML
  disk_paths=$(xmllint --xpath "//disk[@device='disk']/source/@file" "$xml_file" 2>/dev/null | grep -oP 'file="\K[^"]+')
  
  if [ -z "$disk_paths" ]; then
    echo "AVISO: Nenhum disco encontrado no XML de $vm_name" >&2
    continue
  fi
  
  # Restaura cada disco para seu local original
  disk_error=0
  echo "$disk_paths" | while read -r original_path; do
    disk_name=$(basename "$original_path")
    
    # Procura o disco no backup
    backup_disk=$(find "$backup_dir" -maxdepth 1 -type f -name "$disk_name" | head -n1)
    
    if [ -z "$backup_disk" ] || [ ! -f "$backup_disk" ]; then
      echo "ERRO: Disco de backup não encontrado: $disk_name" >&2
      exit 1
    fi
    
    # Cria o diretório de destino se não existir
    sudo mkdir -p "$(dirname "$original_path")"
    
    # Copia o disco
    if ! sudo rsync -aHAX --numeric-ids --sparse "$backup_disk" "$original_path" 2>&1 | grep -E "^(ERRO|ERROR|failed)"; then
      :
    else
      echo "ERRO: Falha ao copiar $disk_name para $vm_name" >&2
      exit 1
    fi
    
    # Ajusta permissões
    sudo chown libvirt-qemu:kvm "$original_path" 2>/dev/null || sudo chown qemu:qemu "$original_path" 2>/dev/null
    sudo chmod 600 "$original_path"
  done
  
  # Verifica se houve erro na cópia dos discos
  if [ $? -ne 0 ]; then
    continue
  fi
  
  # Remove a VM se já existir
  virsh dominfo "$vm_name" >/dev/null 2>&1 && virsh undefine "$vm_name" >/dev/null 2>&1
  
  # Define a VM
  if ! virsh define "$xml_file" >/dev/null 2>&1; then
    echo "ERRO: Falha ao definir a VM $vm_name" >&2
    continue
  fi
  
  # Inicia a VM
  if ! virsh start "$vm_name" >/dev/null 2>&1; then
    echo "ERRO: Falha ao iniciar a VM $vm_name" >&2
    continue
  fi
  
  echo "VM $vm_name restaurada e iniciada"
done

echo "Processo de restauração concluído"
exit 0
