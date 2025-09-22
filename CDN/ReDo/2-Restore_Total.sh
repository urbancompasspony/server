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
##########################################################################################################################
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
##########################################################################################################################
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
##########################################################################################################################
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

# ETAPA 4: Instalar dependências necessárias
##########################################################################################################################
if ! [ -f /srv/restored3.lock ]; then
    echo "=== ETAPA 4: Instalando dependências ==="
    
    # Instalar dependências necessárias para os scripts
    sudo apt update
    sudo apt install -y dialog yq jq curl
    
    sudo touch /srv/restored3.lock
    echo "✓ ETAPA 4 concluída"
fi

# ETAPA 5: Restaurar containers automaticamente
##########################################################################################################################
if ! [ -f /srv/restored4.lock ]; then
    echo "=== ETAPA 5: Restaurando containers automaticamente ==="
    
    # Base URL do seu repositório GitHub
    BASE_URL="https://raw.githubusercontent.com/SEU_USER/SEU_REPO/main/containers"
    
    # Criar lockfile para execução automatizada
    sudo touch /srv/lockfile
    
  declare -A script_map=(
    ["pihole"]="01-pihole"
    ["active-directory"]="02-domain"
    ["unifi"]="03-unifi-net"
    ["mysql"]="04-mysql"
    ["oraclexe21c"]="05-oracle_xe"
    ["nut"]="06-nut-gui"
    ["swc"]="07-simple-web-chat"
    ["honeygain"]="08-honeygain"
    ["pentest"]="09-pentest"
    ["cups"]="10-cups"
    ["nobreak-sms"]="11-SMS-PV"
    ["luanti"]="12-luanti-server"
    ["tailscale"]="13-tailscale"
    ["kasm"]="14-kasm"
    ["kuma"]="15-kuma"
    ["lan-speed-test"]="16-openspeedtest"
    ["chromium-browser"]="17-Chromium"
    ["jellyfin"]="19-jellyfin"
    ["wan-speed-test"]="20-myspeed-tracker"
    ["qbittorrent"]="21-qbittorrent"
    ["aptcache"]="22-apt-cacher"
    ["meshstatic"]="23-meshstatic-web"
    ["plocate"]="24-plocate"
    ["pihole dwservice etc"]="25-ferdium"
    ["nextcloud"]="26-nextcloud"
    ["openfire"]="27-openfire"
    ["filebrowser"]="28-filebrowser"
    ["mariadb"]="29-mariadb"
    ["syslog"]="30-syslog-ng"
    ["reverse-proxy"]="33-reverseproxy"
    ["onlyoffice"]="34-onlyoffice"
    ["apache2"]="36-generic_apache"
    ["ftp"]="37-ftp-server"
    ["dwservice"]="38-ssh-dw"
    ["syncthing"]="42.0-syncthing"
    ["xpra"]="45-xpra-virt-manager"
    ["homarr-web-panel"]="60-homarr"
    ["dashdot"]="61-dashdot"
    ["qdir"]="74-qdirstat"
    ["elasticsearch-db"]="78-elasticsearch"
    ["elastic-search-gui"]="80-sist2"
  )
    
    # Verificar se containers.yaml existe
    if [ -f /srv/containers.yaml ]; then
        echo "Encontrado containers.yaml, processando containers..."
        
        # Criar diretório temporário para scripts
        mkdir -p /tmp/container-scripts
        
        # Obter lista de containers e suas img_base
        yq -r 'to_entries[] | "\(.key):\(.value.img_base)"' /srv/containers.yaml | while IFS=: read -r container_name img_base; do
            if [[ -n "${script_map[$img_base]}" ]]; then
                script_name="${script_map[$img_base]}"
                script_url="${BASE_URL}/${script_name}"
                script_path="/tmp/container-scripts/${script_name}"
                
                echo "Container: $container_name | Imagem: $img_base | Script: $script_name"
                echo "Baixando de: $script_url"
                
                # Fazer download do script
                if curl -sSL "$script_url" -o "$script_path"; then
                    echo "✓ Script baixado com sucesso"
                    chmod +x "$script_path"
                    
                    echo "Executando script para $container_name..."
                    bash "$script_path"
                    echo "✓ Container $container_name processado"
                else
                    echo "✗ Erro ao baixar script de $script_url"
                fi
            else
                echo "⚠ Nenhum script mapeado para img_base: $img_base (container: $container_name)"
            fi
            
            sleep 2  # Pausa entre containers
        done
        
        # Limpar scripts temporários
        rm -rf /tmp/container-scripts
    else
        echo "Arquivo containers.yaml não encontrado, pulando restauração de containers"
    fi
    
    # Remover lockfile após processamento
    sudo rm -f /srv/lockfile
    
    sudo touch /srv/restored4.lock
    echo "✓ ETAPA 5 concluída"
fi

echo "=== RESTORE COMPLETO ==="
echo "Sistema totalmente restaurado!"
echo "- ✓ Configurações do sistema (/etc)"
echo "- ✓ VMs pfSense"
echo "- ✓ Containers Docker"
echo "- ✓ Redes Docker"
