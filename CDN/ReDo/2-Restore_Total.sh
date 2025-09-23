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

# ETAPA 4: Restaurar containers via orchestration + lockfile
##########################################################################################################################
if ! [ -f /srv/restored4.lock ]; then
    echo "=== ETAPA 4: Restaurando containers via orchestration ==="
    
    # URL base do orchestration
    ORCHESTRATION_URL="https://raw.githubusercontent.com/urbancompasspony/docker/main/orchestration.sh"
    
    # Verificar se containers.yaml existe
    if [ -f /srv/containers.yaml ]; then
        echo "Encontrado containers.yaml, processando containers por img_base..."
        
        # Baixar orchestration uma única vez
        echo "Baixando orchestration..."
        if ! curl -sSL "$ORCHESTRATION_URL" -o /tmp/orchestration.sh; then
            echo "❌ Erro ao baixar orchestration"
            exit 1
        fi
        chmod +x /tmp/orchestration.sh
        
        # Mapeamento: img_base -> nome do script no GitHub
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
            ["kuma"]="15-kuma"
            ["lan-speed-test"]="16-openspeedtest"
            ["chromium-browser"]="17-Chromium"
            ["jellyfin"]="19-jellyfin"
            ["wan-speed-test"]="20-myspeed-tracker"
            ["qbittorrent"]="21-qbittorrent"
            ["ferdium"]="25-ferdium"
            ["nextcloud"]="26-nextcloud"
            ["openfire"]="27-openfire"
            ["filebrowser"]="28-filebrowser"
            ["mariadb"]="29-mariadb"
            ["ntfy"]="30-ntfy_server"
            ["reverse-proxy"]="33-reverseproxy"
            ["onlyoffice"]="34-onlyoffice"
            ["apache2"]="36-generic_apache"
            ["ftp"]="37-ftp-server"
            ["dwservice"]="38-ssh-dw"
            ["syncthing"]="42.0-syncthing"
            ["xpra"]="45-xpra-virt-manager"
            ["active-directory-beta"]="58-domain-test"
            ["homarr-web-panel"]="60-homarr"
            ["dashdot"]="61-dashdot"
            ["qdir"]="74-qdirstat"
            ["elasticsearch-db"]="78-elasticsearch"
            ["elastic-search-gui"]="80-sist2"
        )
        
        # Obter todas as img_base únicas do YAML
        unique_images=$(yq -r '[.[] | .img_base] | unique | .[]' /srv/containers.yaml)
        
        echo "Imagens base encontradas:"
        echo "$unique_images" | while read -r img; do
            count=$(yq -r "[.[] | select(.img_base == \"$img\")] | length" /srv/containers.yaml)
            echo "  • $img ($count container(s))"
        done
        echo ""
        
        # Para cada img_base única, processar via orchestration
        echo "$unique_images" | while read -r img_base; do
            if [[ -n "${script_map[$img_base]}" ]]; then
                script_name="${script_map[$img_base]}"
                
                echo "=== Processando img_base: $img_base ==="
                echo "Script correspondente: $script_name"
                
                # Containers que serão processados
                containers=$(yq -r "to_entries[] | select(.value.img_base == \"$img_base\") | .key" /srv/containers.yaml)
                echo "Containers que serão restaurados:"
                echo "$containers" | while read -r cont; do
                    echo "  • $cont"
                done
                
                # Criar lockfile com nome do script
                echo "$script_name" > /srv/lockfile
                
                echo "Executando orchestration para $img_base..."
                bash /tmp/orchestration.sh
                
                # Verificar se foi bem-sucedido
                if [ $? -eq 0 ]; then
                    echo "✓ $img_base processado com sucesso"
                else
                    echo "✗ Erro ao processar $img_base"
                fi
                
                echo "----------------------------------------"
                sleep 3  # Pausa entre diferentes tipos de container
                
            else
                echo "⚠ Nenhum script mapeado para img_base: $img_base"
                containers=$(yq -r "to_entries[] | select(.value.img_base == \"$img_base\") | .key" /srv/containers.yaml)
                echo "Containers afetados:"
                echo "$containers" | while read -r cont; do
                    echo "  • $cont"
                done
                echo ""
            fi
        done
        
        # Limpar lockfile final
        rm -f /srv/lockfile
        
        echo "=== Resumo da restauração ==="
        total_containers=$(yq -r 'keys | length' /srv/containers.yaml)
        echo "Total de containers no YAML: $total_containers"
        
        processed_images=$(echo "$unique_images" | while read -r img; do
            [[ -n "${script_map[$img]}" ]] && echo "$img"
        done | wc -l)
        
        skipped_images=$(echo "$unique_images" | while read -r img; do
            [[ -z "${script_map[$img]}" ]] && echo "$img"
        done)
        
        echo "Imagens processadas: $processed_images"
        if [ -n "$skipped_images" ]; then
            echo "Imagens não mapeadas:"
            echo "$skipped_images" | while read -r img; do
                echo "  ⚠ $img"
            done
        fi
        
    else
        echo "⚠ Arquivo containers.yaml não encontrado, pulando restauração de containers"
    fi
    
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
