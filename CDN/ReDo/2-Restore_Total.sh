#!/bin/bash

# Setup inicial
sudo mkdir -p /srv/containers
sudo mkdir -p /mnt/bkpsys
sudo mount -t ext4 LABEL=bkpsys /mnt/bkpsys

# Encontrar caminho do backup
pathrestore=$(find /mnt/bkpsys -name "*.tar.lz4" 2>/dev/null | head -1 | xargs dirname)

# Restaurar rede Docker (se existir backup)
if [ -f "$pathrestore/docker-network-backup/backup-macvlan.json" ]; then
    cd "$pathrestore/docker-network-backup" || exit
    docker network create -d macvlan \
      --subnet="$(jq -r '.[0].IPAM.Config[0].Subnet' backup-macvlan.json)" \
      --gateway="$(jq -r '.[0].IPAM.Config[0].Gateway' backup-macvlan.json)" \
      -o parent="$(jq -r '.[0].Options.parent' backup-macvlan.json)" \
      "$(jq -r '.[0].Name' backup-macvlan.json)"
fi

# ETAPA 1: Restaurar /etc
if ! [ -f /srv/restored0.lock ]; then
    echo "=== ETAPA 1: Restaurando /etc ==="
    
    # Encontrar arquivo etc mais recente
    etc_file=$(find "$pathrestore" -name "etc-*.tar.lz4" | sort | tail -1)
    
    if [ -n "$etc_file" ]; then
        echo "1. Restaurando /etc completo (exceto fstab)..."
        sudo tar -I 'lz4 -d -c' -xpf "$etc_file" --exclude='etc/fstab' -C /
        
        echo "2. Aplicando merge do fstab..."
        sudo cp /etc/fstab "/etc/fstab.before_merge.$(date +%Y%m%d_%H%M%S)"
        
        # Extrair fstab do backup (correção do sudo redirect)
        sudo tar -I 'lz4 -d -c' -xpf "$etc_file" etc/fstab -O | sudo tee /tmp/fstab.backup > /dev/null
        
        # Merge inteligente
        awk 'FNR==NR { seen[$2]++; next } !seen[$2] { print }' /etc/fstab /tmp/fstab.backup | sudo tee -a /etc/fstab > /dev/null
        
        echo "3. Testando configuração..."
        sudo mount -a --fake && echo "✓ fstab válido" || echo "✗ Erro no fstab!"
        
        rm -f /tmp/fstab.backup
        sudo touch /srv/restored0.lock
        echo "✓ ETAPA 1 concluída"
    fi
fi

# ETAPA 2: Restaurar containers e outros arquivos
if ! [ -f /srv/restored1.lock ]; then
    echo "=== ETAPA 2: Restaurando containers ==="
    
    # Restaurar arquivos de configuração se existirem
    [ -f "$pathrestore/system.yaml" ] && sudo rsync -va "$pathrestore/system.yaml" /srv/
    [ -f "$pathrestore/containers.yaml" ] && sudo rsync -va "$pathrestore/containers.yaml" /srv/
    
    # Restaurar outros arquivos tar.lz4 (exceto etc)
    find "$pathrestore" -type f -name "*.tar.lz4" -not -name "etc*.tar.lz4" -print0 | \
    while IFS= read -r -d '' file; do
        echo "Restaurando: $(basename "$file")"
        sudo tar -I 'lz4 -d -c' -xf "$file" -C /srv/containers
    done
    
    sudo touch /srv/restored1.lock
    echo "✓ ETAPA 2 concluída - Reiniciando..."
    sudo reboot
fi

# ETAPA 3: Restaurar VMs pfSense
if ! [ -f /srv/restored2.lock ]; then
    echo "=== ETAPA 3: Restaurando VMs pfSense ==="
    
    # Restaurar discos pfSense
    find "$pathrestore" -name "*pfsense*" -type f \( -name "*.qcow2" -o -name "*.img" \) | while read -r disk_file; do
        echo "Restaurando disco: $(basename "$disk_file")"
        sudo cp "$disk_file" /var/lib/libvirt/images/
    done
    
    # Restaurar configurações XML das VMs
    find "$pathrestore" -name "*pfsense*-vm-*.xml" | while read -r xml_file; do
        echo "Definindo VM: $(basename "$xml_file")"
        virsh define "$xml_file"
        
        # Extrair nome da VM do arquivo XML
        vm_name=$(basename "$xml_file" | sed 's/-vm-.*\.xml$//')
        virsh start "$vm_name" 2>/dev/null || echo "Falha ao iniciar $vm_name"
    done
    
    sudo touch /srv/restored2.lock
    echo "✓ ETAPA 3 concluída"
fi

echo "=== RESTORE COMPLETO ==="
