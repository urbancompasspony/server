#!/bin/bash

# Lê o diretório de backup
backup_dir=$(sed -n '1p' /srv/scripts/config/backupvm)

if [ -z "$backup_dir" ]; then
  clear
  echo "ERRO: Caminho de backup vazio em /srv/scripts/config/backupvm"
  sleep 3
  exit 1
fi

if [ ! -d "$backup_dir" ]; then
  clear
  echo "ERRO: Diretório de backup não existe: $backup_dir"
  sleep 3
  exit 1
fi

# Detecta interface Docker (será a interface padrão para as VMs)
docker_interface=$(docker network inspect macvlan 2>/dev/null | jq -r '.[0].Options.parent' 2>/dev/null)

if [ -z "$docker_interface" ] || [ "$docker_interface" = "null" ]; then
  # Tenta pegar do system.yaml
  docker_interface=$(yq -r '.Rede.interface_docker' /srv/system.yaml 2>/dev/null)
  
  if [ -z "$docker_interface" ] || [ "$docker_interface" = "null" ]; then
    clear
    echo "ERRO: Não foi possível detectar a interface Docker"
    echo "Execute o restore completo primeiro ou configure a rede Docker"
    sleep 3
    exit 1
  fi
fi

echo "=== Restauração de VMs ==="
echo "Interface Docker detectada: $docker_interface"
echo "Esta interface será usada caso a interface original não exista"
echo ""

# Procura todos os XMLs de VMs no backup
xml_files=$(find "$backup_dir" -maxdepth 1 -type f -name "*-vm.xml")

if [ -z "$xml_files" ]; then
  clear
  echo "ERRO: Nenhum XML de VM encontrado em $backup_dir"
  sleep 3
  exit 1
fi

# Função para mapear interfaces no XML
function map_xml_interfaces {
  local xml_file="$1"
  local new_interface="$2"
  
  echo "  🔍 Verificando interfaces no XML..."
  
  # Extrai interfaces do tipo 'direct' no XML
  xml_interfaces=($(awk '/<interface type=.direct.>/,/<\/interface>/ {if ($0 ~ /dev=/) print}' "$xml_file" | \
    grep -oP "dev='\K[^']*" | \
    sort -u))
  
  if [ ${#xml_interfaces[@]} -eq 0 ]; then
    echo "  ✓ Nenhuma interface de rede no XML"
    return 0
  fi
  
  echo "  📋 Interfaces encontradas no XML:"
  printf '     • %s\n' "${xml_interfaces[@]}"
  
  # Verifica quais interfaces existem no sistema
  missing_count=0
  for xml_int in "${xml_interfaces[@]}"; do
    if ! ip link show "$xml_int" >/dev/null 2>&1; then
      echo "  ⚠️  Interface $xml_int não existe no sistema"
      ((missing_count++))
    fi
  done
  
  # Se todas existem, não modifica
  if [ $missing_count -eq 0 ]; then
    echo "  ✅ Todas as interfaces existem - usando XML original"
    return 0
  fi
  
  # Backup do XML original
  if [ ! -f "$xml_file.original" ]; then
    cp "$xml_file" "$xml_file.original"
    echo "  💾 Backup criado: $xml_file.original"
  fi
  
  # Substitui TODAS as interfaces pela interface Docker
  echo "  🔧 Remapeando interfaces para: $new_interface"
  for xml_int in "${xml_interfaces[@]}"; do
    sed -i "s/dev='$xml_int'/dev='$new_interface'/g" "$xml_file"
    echo "     • $xml_int → $new_interface"
  done
  
  echo "  ✅ XML modificado com sucesso"
  return 0
}

# Restaura cada VM encontrada
echo "$xml_files" | while read -r xml_file; do
  vm_name=$(basename "$xml_file" | sed 's/-vm\.xml$//')
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🖥️  Restaurando VM: $vm_name"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Extrai os caminhos originais dos discos do XML
  disk_paths=$(xmllint --xpath "//disk[@device='disk']/source/@file" "$xml_file" 2>/dev/null | grep -oP 'file="\K[^"]+')
  
  if [ -z "$disk_paths" ]; then
    echo "  ⚠️  AVISO: Nenhum disco encontrado no XML de $vm_name"
    continue
  fi
  
  # Restaura cada disco para seu local original
  disk_error=0
  echo "  📦 Restaurando discos..."
  echo "$disk_paths" | while read -r original_path; do
    disk_name=$(basename "$original_path")
    
    # Procura o disco no backup
    backup_disk=$(find "$backup_dir" -maxdepth 1 -type f -name "$disk_name" | head -n1)
    
    if [ -z "$backup_disk" ] || [ ! -f "$backup_disk" ]; then
      clear
      echo "  ❌ ERRO: Disco de backup não encontrado: $disk_name"
      sleep 3
      exit 1
    fi
    
    # Cria o diretório de destino se não existir
    sudo mkdir -p "$(dirname "$original_path")"
    
    # Copia o disco
    echo "     • Copiando: $disk_name"
    if ! sudo rsync -aHAX --numeric-ids --sparse "$backup_disk" "$original_path" 2>&1 | grep -E "^(ERRO|ERROR|failed)"; then
      :
    else
      echo "  ❌ ERRO: Falha ao copiar $disk_name"
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
  
  echo "  ✅ Discos restaurados"
  
  # NOVO: Copia XML para área de trabalho e mapeia interfaces
  xml_work="/tmp/${vm_name}-restore.xml"
  cp "$xml_file" "$xml_work"
  
  map_xml_interfaces "$xml_work" "$docker_interface"
  
  # Remove a VM se já existir
  if virsh dominfo "$vm_name" >/dev/null 2>&1; then
    echo "  🗑️  Removendo VM existente..."
    virsh destroy "$vm_name" >/dev/null 2>&1
    virsh undefine "$vm_name" >/dev/null 2>&1
  fi
  
  # Define a VM usando o XML modificado
  echo "  📝 Definindo VM..."
  if ! virsh define "$xml_work" >/dev/null 2>&1; then
    echo "  ❌ ERRO: Falha ao definir a VM $vm_name"
    continue
  fi
  
  echo "  ✅ VM definida com sucesso"
  
  # Inicia a VM
  echo "  🚀 Iniciando VM..."
  if virsh start "$vm_name" >/dev/null 2>&1; then
    echo "  ✅ VM $vm_name iniciada com sucesso"
  else
    echo "  ⚠️  Tentando iniciar com --force-boot..."
    if virsh start "$vm_name" --force-boot >/dev/null 2>&1; then
      echo "  ✅ VM iniciada (forçada)"
    else
      echo "  ❌ ERRO: Falha ao iniciar a VM $vm_name"
      echo "  📝 Verifique: virsh dominfo $vm_name"
    fi
  fi
  
  # Salva XML final
  sudo cp "$xml_work" "/var/lib/libvirt/qemu/$vm_name.xml" 2>/dev/null
  
  sleep 2
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Processo de restauração concluído"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sleep 2
exit 0
