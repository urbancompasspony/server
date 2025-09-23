#!/bin/bash

# Setup inicial
sudo mkdir -p /srv/containers
sudo mkdir -p /mnt/bkpsys
sudo mount -t ext4 LABEL=bkpsys /mnt/bkpsys

# Encontrar caminho do backup
pathrestore=$(find /mnt/bkpsys -name "*.tar.lz4" 2>/dev/null | head -1 | xargs dirname)

# Restaurar rede docker macvlan (se existir backup)
if [ -f "$pathrestore/docker-network-backup/macvlan.json" ]; then
    cd "$pathrestore/docker-network-backup" || exit
    docker network create -d macvlan \
      --subnet="$(jq -r '.[0].IPAM.Config[0].Subnet' macvlan.json)" \
      --gateway="$(jq -r '.[0].IPAM.Config[0].Gateway' macvlan.json)" \
      -o parent="$(jq -r '.[0].Options.parent' macvlan.json)" \
      "$(jq -r '.[0].Name' macvlan.json)"
fi

# ETAPA 1: Restaurar /etc
##########################################################################################################################
if ! [ -f /srv/restored1.lock ]; then
    echo "=== ETAPA 1: Restaurando /etc ==="
    
    # Encontrar arquivo etc mais recente
    etc_file=$(find "$pathrestore" -name "etc-*.tar.lz4" | sort | tail -1)
    
    if [ -n "$etc_file" ]; then
        echo "1. Restaurando /etc completo (exceto fstab)..."
        sudo tar -I 'lz4 -d -c' -xpf "$etc_file" -C /
        
        echo "2. Procurando backup do fstab..."
        # Procurar arquivo fstab backup (formato: fstab-YYYYMMDD_HHMMSS.backup)
        fstab_backup=$(find "$pathrestore" -name "fstab-*.backup" | sort | tail -1)
        
        if [ -n "$fstab_backup" ]; then
            echo "Encontrado: $(basename "$fstab_backup")"
            echo "3. Fazendo backup do fstab atual..."
            sudo cp /etc/fstab "/etc/fstab.bkp-preventivo.$(date +%Y%m%d_%H%M%S)"
            
            echo "4. Aplicando merge inteligente do fstab..."
            # Merge: manter entradas atuais, adicionar só as que não existem do backup
            awk 'FNR==NR { seen[$2]++; next } !seen[$2] { print }' /etc/fstab "$fstab_backup" | sudo tee -a /etc/fstab > /dev/null
            
            echo "5. Testando configuração..."
            if sudo mount -a --fake; then
                echo "✓ fstab válido"
            else
                echo "✗ Erro no fstab! Restaurando backup..."
                sudo cp "/etc/fstab.before_restore.$(date +%Y%m%d)_"* /etc/fstab 2>/dev/null || true
            fi
        else
            echo "⚠ Nenhum backup de fstab encontrado em $pathrestore"
        fi
        
        sudo touch /srv/restored0.lock
        echo "✓ ETAPA 1 concluída"
    else
        echo "❌ Nenhum arquivo etc-*.tar.lz4 encontrado em $pathrestore"
        echo "Arquivos disponíveis:"
        find "$pathrestore" -name "*.tar.lz4" 2>/dev/null || echo "Nenhum arquivo .tar.lz4 encontrado"
    fi
else
    echo "⏭ ETAPA 1 já executada (lock existe)"
fi

# ETAPA 2: Restaurar containers e outros arquivos
##########################################################################################################################
if ! [ -f /srv/restored2.lock ]; then
    echo "=== ETAPA 2: Restaurando containers (automático 24h) ==="
    
    # Restaurar YAMLs
    [ -f "$pathrestore/system.yaml" ] && sudo rsync -va "$pathrestore/system.yaml" /srv/
    [ -f "$pathrestore/containers.yaml" ] && sudo rsync -va "$pathrestore/containers.yaml" /srv/
    
    echo "🕐 Buscando backups das últimas 24h entre ~320 arquivos..."
    
    # Método mais eficiente para muitos arquivos
    recent_container_file=$(find "$pathrestore" -type f -name "*.tar.lz4" -not -name "etc*.tar.lz4" -newermt "24 hours ago" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
    
    if [ -n "$recent_container_file" ]; then
        echo "📦 Restaurando: $(basename "$recent_container_file")"
        echo "📅 Data: $(stat -c '%y' "$recent_container_file" | cut -d'.' -f1)"
        
        sudo tar -I 'lz4 -d -c' -xf "$recent_container_file" -C /srv/containers
        echo "✅ Containers restaurados das últimas 24h"
        
    else
        echo "⚠ Nenhum backup das últimas 24h, usando o mais recente disponível"
        fallback_file=$(find "$pathrestore" -type f -name "*.tar.lz4" -not -name "etc*.tar.lz4" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
        
        if [ -n "$fallback_file" ]; then
            echo "📦 Fallback: $(basename "$fallback_file")"
            echo "📅 Data: $(stat -c '%y' "$fallback_file" | cut -d'.' -f1)"
            sudo tar -I 'lz4 -d -c' -xf "$fallback_file" -C /srv/containers
            echo "✅ Containers restaurados (backup mais recente)"
        else
            echo "❌ Nenhum backup encontrado!"
        fi
    fi
    
    sudo touch /srv/restored2.lock
    echo "✓ ETAPA 2 concluída"
else
    echo "⏭ ETAPA 2 já executada (lock existe)"
fi

# ETAPA 3: Restaurar VMs pfSense (CORRIGIDA)
##########################################################################################################################
if ! [ -f /srv/restored3.lock ]; then
    echo "=== ETAPA 3: Restaurando VMs pfSense ==="
    
    # Restaurar discos pfSense (sempre 1 versão) - busca case-insensitive
    echo "📦 Restaurando discos pfSense..."
    find "$pathrestore" -iname "*pfsense*" -type f \( -name "*.qcow2" -o -name "*.img" \) | while read -r disk_file; do
        echo "Restaurando disco: $(basename "$disk_file")"
        sudo rsync -va "$disk_file" /var/lib/libvirt/images/
    done
    
    # Procurar XMLs mais recentes para cada VM pfSense
    echo ""
    echo "🔧 Configurando VMs com XMLs mais recentes..."
    
    # Encontrar todos os XMLs únicos (por nome base da VM) - busca case-insensitive
    vm_bases=$(find "$pathrestore" -iname "*pfsense*.xml" -exec basename {} \; | sed 's/-vm-.*\.xml$//' | sort -u)
    
    # Debug: mostrar o que foi encontrado
    echo "🔍 Debug - XMLs encontrados:"
    find "$pathrestore" -iname "*pfsense*.xml" | while read -r xml; do
        echo "   Encontrado: $(basename "$xml")"
    done
    
    echo "🔍 Debug - Nomes base extraídos:"
    echo "$vm_bases" | while read -r base; do
        echo "   Nome base: '$base'"
    done
    
    if [ -n "$vm_bases" ]; then
        echo "$vm_bases" | while read -r vm_base; do
            echo "🔍 Processando VM base: '$vm_base'"
            
            # Para cada VM base, encontrar o XML mais recente (busca case-insensitive)
            most_recent_xml=$(find "$pathrestore" -iname "${vm_base}-vm-*.xml" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
            
            if [ -n "$most_recent_xml" ]; then
                echo "🖥️  VM: $vm_base"
                echo "   XML mais recente: $(basename "$most_recent_xml")"
                echo "   Caminho completo: $most_recent_xml"
                echo "   Data: $(stat -c '%y' "$most_recent_xml" | cut -d'.' -f1)"
                
                # Verificar se o arquivo XML existe e é legível
                if [ -r "$most_recent_xml" ]; then
                    # Definir a VM
                    echo "   🔧 Definindo VM..."
                    if virsh define "$most_recent_xml"; then
                        echo "   ✅ VM definida com sucesso"
                        
                        # Tentar iniciar a VM
                        if virsh start "$vm_base" 2>/dev/null; then
                            echo "   ✅ VM iniciada com sucesso"
                        else
                            echo "   ⚠️  Falha ao iniciar $vm_base (normal se já estiver rodando)"
                        fi
                    else
                        echo "   ❌ Falha ao definir VM $vm_base"
                        echo "   🔍 Verificando conteúdo do XML..."
                        head -5 "$most_recent_xml"
                    fi
                else
                    echo "   ❌ Arquivo XML não encontrado ou não legível: $most_recent_xml"
                fi
                
                # Mostrar outros XMLs disponíveis para esta VM (informativo)
                other_xmls=$(find "$pathrestore" -iname "${vm_base}-vm-*.xml" | wc -l)
                if [ "$other_xmls" -gt 1 ]; then
                    echo "   ℹ️  Outros $((other_xmls-1)) XML(s) disponível(is) mas não usado(s)"
                fi
                echo ""
            else
                echo "   ❌ Nenhum XML encontrado para VM base: $vm_base"
            fi
        done
    else
        echo "⚠️  Nenhum XML pfSense encontrado"
        echo "XMLs disponíveis no diretório:"
        find "$pathrestore" -name "*.xml" | head -10 | while read -r xml; do
            echo "   - $(basename "$xml")"
        done
        echo ""
        echo "🔍 Testando busca case-insensitive:"
        find "$pathrestore" -iname "*pfsense*.xml" | while read -r xml; do
            echo "   - $(basename "$xml")"
        done
    fi
    
    sudo touch /srv/restored3.lock
    echo "✅ ETAPA 3 concluída"
else
    echo "⏭ ETAPA 3 já executada (lock existe)"
fi

# ETAPA 4: Restaurar containers automaticamente (VERSÃO CORRIGIDA)
##########################################################################################################################
if ! [ -f /srv/restored4.lock ]; then
    echo "=== ETAPA 4: Restaurando containers automaticamente ==="
    
    # Base URL do seu repositório GitHub
    BASE_URL="https://github.com/urbancompasspony/docker/blob/main"
    
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
    sudo rsync -va 
    if [ -f /srv/containers.yaml ]; then
        echo "Encontrado containers.yaml, processando containers..."
        
        # Criar diretório temporário para scripts
        mkdir -p /tmp/container-scripts
        
        # CORREÇÃO: Processar cada container individualmente
        yq -r 'keys[]' /srv/containers.yaml | while read -r container_name; do
            echo "=== Processando container: $container_name ==="
            
            # Obter img_base para este container específico
            img_base=$(yq -r ".\"$container_name\".img_base" /srv/containers.yaml)
            
            if [[ -n "${script_map[$img_base]}" ]]; then
                script_name="${script_map[$img_base]}"
                script_url="${BASE_URL}/${script_name}"
                script_path="/tmp/container-scripts/${script_name}"
                
                echo "Container: $container_name"
                echo "Imagem base: $img_base"
                echo "Script: $script_name"
                echo "URL: $script_url"
                
                # Fazer download do script (só uma vez por script único)
                if [ ! -f "$script_path" ]; then
                    echo "Baixando script..."
                    if curl -sSL "$script_url" -o "$script_path"; then
                        echo "✓ Script baixado com sucesso"
                        chmod +x "$script_path"
                    else
                        echo "✗ Erro ao baixar script de $script_url"
                        continue
                    fi
                else
                    echo "✓ Script já existe em cache"
                fi
                
                echo "Executando script para container $container_name..."
                
                # IMPORTANTE: O script vai usar o lockfile e buscar as configurações
                # específicas deste container no containers.yaml através da função
                # process_container que está nos scripts originais
                bash "$script_path"
                
                echo "✓ Container $container_name processado"
                echo "----------------------------------------"
                
            else
                echo "⚠ Nenhum script mapeado para img_base: $img_base (container: $container_name)"
            fi
            
            sleep 3  # Pausa entre containers para evitar conflitos
        done
        
        # Limpar scripts temporários
        rm -rf /tmp/container-scripts
        
        echo "=== Resumo final ==="
        echo "Containers processados:"
        yq -r 'keys[]' /srv/containers.yaml | while read -r container; do
            img_base=$(yq -r ".\"$container\".img_base" /srv/containers.yaml)
            echo "  • $container ($img_base)"
        done
        
    else
        echo "Arquivo containers.yaml não encontrado, pulando restauração de containers"
    fi
    
    # Remover lockfile após processamento
    sudo rm -f /srv/lockfile
    
    sudo touch /srv/restored4.lock
    echo "✓ ETAPA 4 concluída"
else
    echo "⏭ ETAPA 4 já executada (lock existe)"
fi

echo "=== RESTORE COMPLETO ==="
echo "- ✓ Configurações do sistema (/etc)"
echo "- ✓ VMs pfSense"
echo "- ✓ Containers Docker"
echo "- ✓ Redes Docker"
echo "reiniciando..."
sleep 5
reboot
