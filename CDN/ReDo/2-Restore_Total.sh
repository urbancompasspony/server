#!/bin/bash
yamlbase="/srv/system.yaml"
yamlextra="/srv/containers.yaml"
export yamlbase
export yamlextra
# ETAPA X - Montagem do disco de backup
##########################################################################################################################
sudo mkdir -p /srv/containers; sudo mkdir -p /mnt/bkpsys
if mountpoint -q /mnt/bkpsys; then
  echo "✓ Backup já está montado"
else
  echo "Montando backup..."
  if sudo mount -t ext4 LABEL=bkpsys /mnt/bkpsys; then
    echo "✓ Backup montado com sucesso"
    echo "✓ ETAPA 0 concluída"
  else
    clear
    echo ""; echo "✗ Não conseguimos encontrar o dispositivo com backup do servidor!"
    sleep 4
    echo "Verifique os dispositivos de armazenamento."
    sleep 3
    echo "Saindo..."
    sleep 2
    exit 1
  fi
fi
# ETAPA 00 - Verificação Preventiva
##########################################################################################################################
if [ -f /mnt/bkpsys/system.yaml ]; then
  CURRENT_MACHINE_ID=$(cat /etc/machine-id 2>/dev/null)
  BACKUP_MACHINE_ID=$(yq -r '.Redes.macvlan.machine_id // empty' /mnt/bkpsys/system.yaml 2>/dev/null)
  
  # Verificar se machine-id do backup está vazio ou inválido
  if [ -z "$BACKUP_MACHINE_ID" ] || [ "$BACKUP_MACHINE_ID" = "null" ] || [ "$BACKUP_MACHINE_ID" = "empty" ]; then
    clear
    echo ""
    echo "ERRO DE VALIDACAO!"
    sleep 2
    echo "O machine-id no backup esta vazio, nulo ou invalido."
    sleep 3
    echo "Backup: '$BACKUP_MACHINE_ID'"
    sleep 3
    echo "Isso indica um backup corrompido ou incompleto."
    sleep 4
    echo "Nao e possivel determinar com seguranca se este restore e valido."
    sleep 4
    echo "Verifique a integridade do backup ou use um backup mais recente."
    sleep 3
    echo "Saindo por seguranca..."
    sleep 2
    exit 1
  fi
  
  # Verificar se machine-id atual está disponível
  if [ -z "$CURRENT_MACHINE_ID" ]; then
    clear
    echo ""
    echo "ERRO: Nao foi possivel ler o machine-id do sistema atual!"
    sleep 3
    echo "Verifique o arquivo /etc/machine-id"
    sleep 2
    exit 1
  fi
  
  # Verificar se são idênticos (proteção anti-auto-restore)
  if [ "$CURRENT_MACHINE_ID" = "$BACKUP_MACHINE_ID" ]; then
    clear
    echo ""
    echo "BLOQUEIO DE SEGURANCA ATIVADO!"
    sleep 2
    echo "O machine-id atual ($CURRENT_MACHINE_ID) e identico ao do backup."
    sleep 3
    echo "Isso indica que voce esta tentando restaurar um backup sobre o proprio sistema que o gerou."
    sleep 4
    echo "Esta operacao e PERIGOSA e pode causar perda de dados ou corrupcao do sistema!"
    sleep 4
    echo "Para restaurar, execute em um sistema diferente ou reformate este sistema."
    sleep 3
    echo "Saindo por seguranca..."
    sleep 2
    exit 1
  fi
  
  echo "Machine-id validado: sistema diferente do backup - prosseguindo..."
  
else
  clear
  echo ""
  echo "AVISO: Arquivo system.yaml nao encontrado no backup!"
  sleep 3
  echo "Nao e possivel validar a seguranca do restore."
  echo "Saindo por seguranca..."
  sleep 2
  exit 1
fi

if [ -f /srv/restored8.lock ]; then
  clear
  echo ""
  echo "⏭ ESTE SERVIDOR JÁ FOI RESTAURADO COMPLETAMENTE! (lock existe)"
  sleep 2
  echo "Se o sistema apresenta falhas nos serviços, recomendo que formate e refaça o sistema restaurando novamente."
  sleep 4
  echo "Saindo..."
  sleep 2
  exit 1
fi

if [ "$(hostname)" = "ubuntu-server" ]; then
  :;
else
  clear
  echo ""; echo "ATENÇÃO:"
  sleep 1
  echo "Este sistema já está pré-definido com o hostname $(hostname)."
  sleep 4
  echo "Entendemos que você está tentando restaurar um backup do servidor sobre um servidor legítimo em execução."
  sleep 5
  echo "Se realmente quiser fazer isso, renomeie o hostname para ubuntu-server e reexecute este utilitario!"
  sleep 5
  exit 1
fi
# ETAPA 01 - Montagem das redes
##########################################################################################################################
if ! [ -f /srv/restored1.lock ]; then
  pathrestore=$(find /mnt/bkpsys -name "*.tar.lz4" 2>/dev/null | head -1 | xargs dirname)
  export pathrestore
  
  if [ -f "$pathrestore/docker-network-backup/macvlan.json" ]; then
    cd "$pathrestore/docker-network-backup" || exit
    
    # Pega a interface do backup
    original_parent="$(jq -r '.[0].Options.parent' macvlan.json)"
    
    # Verifica se a interface original existe
    if ip link show "$original_parent" >/dev/null 2>&1; then
        echo "Interface original $original_parent encontrada - usando backup direto!"
        
        docker network create -d macvlan \
        --subnet="$(jq -r '.[0].IPAM.Config[0].Subnet' macvlan.json)" \
        --gateway="$(jq -r '.[0].IPAM.Config[0].Gateway' macvlan.json)" \
        -o parent="$original_parent" \
        "$(jq -r '.[0].Name' macvlan.json)"
        
    else
        echo "Interface $original_parent nao encontrada - configuracao interativa necessaria"
        
        if curl -sSL https://raw.githubusercontent.com/urbancompasspony/docker/refs/heads/main/Scripts/macvlan/set | sudo bash; then
            echo "Configuracao de rede concluida com sucesso"
        else
            echo "ERRO: Falha na configuracao de rede"
            exit 1
        fi
    fi
    
    sudo touch /srv/restored1.lock
    echo "ETAPA 1 concluida"
  fi
else
  echo "ETAPA 1 ja executada (lock existe)"
fi
# ETAPA 02 - Restaurando sistema operacional /etc/
##########################################################################################################################
if ! [ -f /srv/restored2.lock ]; then
    echo "=== ETAPA 2: Restaurando /etc ==="
    
    # Encontrar arquivo etc mais recente
    etc_file=$(find "$pathrestore" -name "etc-*.tar.lz4" | sort | tail -1)
    
    if [ -n "$etc_file" ]; then
        echo "1. Restaurando /etc completo (exceto fstab)..."
        sudo tar -I 'lz4 -d -c' -xpf "$etc_file" -C /
        
        echo "2. Procurando backup do fstab..."
        # Procurar arquivo fstab backup (formato: fstab-YYYYMMDD_HHMMSS.backup)
        fstab_backup=$(find "$pathrestore" -name "fstab.backup" | sort | tail -1)
        
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

        # Limpeza total de dados inuteis para deixar o fstab conciso!
        sudo sed -i '/^[[:space:]]*#/d; /^[[:space:]]*$/d; s/[[:space:]]*$//' /etc/fstab

        sudo touch /srv/restored2.lock
        echo "✓ ETAPA 2 concluída"
    else
        echo "❌ Nenhum arquivo etc-*.tar.lz4 encontrado em $pathrestore"
        echo "Arquivos disponíveis:"
        find "$pathrestore" -name "*.tar.lz4" 2>/dev/null || echo "Nenhum arquivo .tar.lz4 encontrado"
    fi
else
    echo "⏭ ETAPA 2 já executada (lock existe)"
fi

# ETAPA 03 - Restaurando VM pfSense
##########################################################################################################################
if ! [ -f /srv/restored3.lock ]; then
    echo "=== ETAPA 3: Restaurando VMs pfSense ==="
    
    # Restaurar discos pfSense (sempre 1 versão) - busca case-insensitive
    echo "📦 Restaurando discos pfSense..."
    find "$pathrestore" -iname "*pfsense*" -type f | while read -r disk_file; do
      # Verificar se é um arquivo de disco virtual
      file_type=$(file -b "$disk_file")
      if echo "$file_type" | grep -qi "qemu\|disk\|image\|data"; then
        echo "Restaurando disco: $(basename "$disk_file")"
        echo "  Tipo: $file_type"
        sudo rsync -aHAXv --numeric-ids --sparse "$disk_file" /var/lib/libvirt/images/
      else
        echo "⏭ Ignorando $(basename "$disk_file") (não é disco virtual)"
        echo "  Tipo: $file_type"
      fi
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
# ETAPA 04 - Restaurar cada container no seu devido lugar apenas
##########################################################################################################################
if ! [ -f /srv/restored4.lock ]; then
    echo "=== ETAPA 4: Restaurando containers (mais recente de cada) ==="
    
    # Restaurar YAMLs
    [ -f "$pathrestore/system.yaml" ] && sudo rsync -aHAXv --numeric-ids --sparse "$pathrestore/system.yaml" /srv/
    [ -f "$pathrestore/containers.yaml" ] && sudo rsync -aHAXv --numeric-ids --sparse "$pathrestore/containers.yaml" /srv/
    
    echo "🔍 Analisando arquivos de container..."
    
    # Criar diretório se não existir
    sudo mkdir -p /srv/containers
    
    # Encontrar todos os arquivos .tar.lz4 (exceto etc)
    temp_file="/tmp/container_analysis.$$"
    find "$pathrestore" -name "*.tar.lz4" -not -name "etc*.tar.lz4" -printf '%T@ %p\n' | sort -k2 > "$temp_file"
    
    # Extrair nomes base únicos e pegar o mais recente de cada
    declare -A latest_files
    
    while read -r timestamp filepath; do
        filename=$(basename "$filepath")
        # Extrair nome base (tudo antes da data)
        # Ex: openspeedtest-24_09_25.tar.lz4 -> openspeedtest
        basename_clean=$(echo "$filename" | sed 's/-[0-9][0-9]_[0-9][0-9]_[0-9][0-9]\.tar\.lz4$//')
        
        # Guardar o mais recente (maior timestamp) para cada nome base
        if [[ -z "${latest_files[$basename_clean]}" ]] || (( $(echo "$timestamp > ${latest_files[$basename_clean]%% *}" | bc -l) )); then
            latest_files[$basename_clean]="$timestamp $filepath"
        fi
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    # Restaurar os arquivos selecionados
    if [ ${#latest_files[@]} -gt 0 ]; then
        echo "📦 Encontrados $(echo ${#latest_files[@]}) containers únicos:"
        
        for basename_clean in "${!latest_files[@]}"; do
            filepath=$(echo "${latest_files[$basename_clean]}" | cut -d' ' -f2-)
            filename=$(basename "$filepath")
            echo "  - $basename_clean: $filename"
            
            echo "    Extraindo: $filename"
            sudo tar -I 'lz4 -d -c' -xf "$filepath" -C /srv/containers
        done
        
        echo "✅ Containers restaurados (mais recente de cada tipo)"
    else
        echo "❌ Nenhum arquivo de container encontrado!"
    fi
    
    sudo touch /srv/restored4.lock
    echo "✓ ETAPA 4 concluída"
else
    echo "⏭ ETAPA 4 já executada (lock existe)"
fi
# ETAPA 05 - Inicializar os containers que foram restaurados da etapa anterior
##########################################################################################################################
if ! [ -f /srv/restored5.lock ]; then
    echo "=== ETAPA 5: Restaurando containers via orchestration ==="
    
    # URL correta do orchestration
    ORCHESTRATION_URL="https://raw.githubusercontent.com/urbancompasspony/server/refs/heads/main/orchestration"
    
    # Verificar se containers.yaml existe
    if [ -f /srv/containers.yaml ]; then
        echo "Encontrado containers.yaml, processando containers por img_base..."
        
        # Baixar orchestration apenas se não existir
        if [ ! -f /tmp/orchestration ]; then
            echo "Baixando orchestration..."
            if ! curl -sSL "$ORCHESTRATION_URL" -o /tmp/orchestration; then
                echo "❌ Erro ao baixar orchestration"
                exit 1
            fi
            chmod +x /tmp/orchestration
            echo "✓ Orchestration baixado"
        else
            echo "✓ Aproveitando orchestration existente"
        fi
        
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
                bash /tmp/orchestration
                
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
        
        echo "✓ Restauração automática concluída"
        
    else
        echo "⚠ Arquivo containers.yaml não encontrado, pulando restauração de containers"
    fi
    
    sudo touch /srv/restored5.lock
    echo "✓ ETAPA 5 concluída"
else
    echo "⏭ ETAPA 5 já executada (lock existe)"
fi
# ETAPA 06 - Restauração Crontab
##########################################################################################################################
if ! [ -f /srv/restored6.lock ]; then
  sudo crontab "$pathrestore"/crontab-bkp
  sudo touch /srv/restored6.lock
  echo "✓ ETAPA 6 concluída"
else
  echo "⏭ ETAPA 6 já executada (lock existe)"
fi
# ETAPA 07 - Finalização
##########################################################################################################################
datetime0=$(date +"%d/%m/%Y - %H:%M")
sudo yq -i ".Informacoes.Data_Ultima_Reinstalacao = \"${datetime0}\"" "$yamlbase"
echo "=== RESTORE COMPLETO ==="
sleep 3
echo "Reiniciando..."
sudo touch /srv/restored7.lock
sleep 3
sudo reboot
exit 0
