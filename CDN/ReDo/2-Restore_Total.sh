#!/bin/bash
yamlbase="/srv/system.yaml"
yamlextra="/srv/containers.yaml"
export yamlbase
export yamlextra
# ETAPA X - Montagem do disco de backup
##########################################################################################################################
function restorefunc {
  pathrestore=$(find /mnt/bkpsys -name "*.tar.lz4" 2>/dev/null | head -1 | xargs dirname)
  export pathrestore
}
sudo mkdir -p /srv/containers; sudo mkdir -p /mnt/bkpsys
if mountpoint -q /mnt/bkpsys; then
  echo "✓ Backup já está montado"
  restorefunc
else
  echo "Montando backup..."
  if sudo mount -t ext4 LABEL=bkpsys /mnt/bkpsys; then
    echo "✓ Backup montado com sucesso"
    echo "✓ ETAPA 0 concluída"
    restorefunc
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
if [ -f "$pathrestore"/system.yaml ]; then
  CURRENT_MACHINE_ID=$(cat /etc/machine-id 2>/dev/null)
  BACKUP_MACHINE_ID=$(yq -r '.Informacoes.machine_id' "$pathrestore"/system.yaml 2>/dev/null)
  # Verificar se machine-id do backup está vazio ou inválido
  if [ -z "$BACKUP_MACHINE_ID" ] || [ "$BACKUP_MACHINE_ID" = "null" ]; then
    clear
    echo ""
    echo "ERRO 01: VALIDACAO!"
    echo "O machine-id no backup esta nulo ou invalido."
    echo "Operacao cancelada. Saindo em 5 segundos..."
    sleep 5
    exit 1
  fi
  # Verificar se são idênticos (proteção anti-auto-restore)
  if [ "$CURRENT_MACHINE_ID" = "$BACKUP_MACHINE_ID" ]; then
    clear
    echo ""
    echo "ERRO 02: BLOQUEIO DE SEGURANCA!"
    echo "Para restaurar, reexecute essa restauracao em outro sistema ou reformate este."
    echo "Operacao cancelada. Saindo em 5 segundos..."
    sleep 5
    exit 1
  fi
  if [ -f /srv/restored8.lock ]; then
    clear
    echo ""
    echo "ERRO 03: ⏭ ESTE SERVIDOR JÁ FOI RESTAURADO COMPLETAMENTE! (lock existe)"
    echo "Se o sistema apresenta falhas nos serviços, recomendo que formate e refaça o sistema restaurando novamente."
    echo "Operacao cancelada. Saindo em 5 segundos..."
    sleep 5
    exit 1
  fi
  if [ "$(hostname)" = "ubuntu-server" ]; then
    :;
  else
    clear
    echo ""; echo ""
    echo "ERRO 04: Este sistema ja esta pre-definido com o hostname $(hostname)."
    echo "Entendemos que você esta tentando restaurar um backup do servidor sobre um servidor legitimo em execucao."
    echo "Se realmente quiser fazer isso, renomeie este sistema para o hostname 'ubuntu-server' e reexecute este utilitario!"
    echo "Operacao cancelada. Saindo em 5 segundos..."
    sleep 5
    exit 1
  fi
else
  clear
  echo ""
  echo "ERRO 05: Arquivo system.yaml nao encontrado no backup!"
  echo "Nao e possivel validar este backup encontrado."
  echo "Operacao cancelada. Saindo em 5 segundos..."
  sleep 5
  exit 1
fi

# Nenhum erro??? Então vamos seguir!
  clear
  echo "ESTA TUDO CORRETO! TUDO FOI DEVIDAMENTE VALIDADO."
  sleep 1
  echo "5"
  echo "O SERVIDOR SERÁ COMPLETAMENTE RESTAURADO BASEADO NO BACKUP ENCONTRADO!"
  sleep 1
  echo "4"
  echo "NÃO TENTE INTERAGIR COM O SISTEMA DURANTE A RESTAURAÇÃO COMPLETA."
  sleep 1
  echo "3"
  echo "SE POSSÍVEL DESCONECTE TECLADO E MOUSE, NÃO INTERAJA COM ABSOLUTAMENTE NADA ATÉ CONCLUIR!"
  sleep 1
  echo "2"
  echo "SE QUISER DESISTIR AGORA PRESSIONE   CTRL + C"
  sleep 1
  echo "1"
  echo "NÃO DESLIGUE O SERVIDOR ATÉ O MOMENTO DO REINÍCIO AUTOMÁTICO."
  sleep 1
  echo "0"
  echo "Restauração Iniciada..."
  echo "Tenha uma boa sorte!"
  sleep 3
  clear
# ETAPA 01 - Montagem das redes
##########################################################################################################################
NETPLAN_FILE="/etc/netplan/50-cloud-init.yaml"
function auto_configure_netplan {
    backup_file="/tmp/netplan_backup_$(date +%s).yaml"
    sudo cp "$NETPLAN_FILE" "$backup_file" 2>/dev/null
    up_interfaces=()
    down_interfaces=()
    
    # Fixed: Use glob pattern instead of ls | grep
    for interface in /sys/class/net/en*; do
        # Check if the glob matched anything
        [ -e "$interface" ] || continue
        
        # Extract just the interface name
        interface_name=$(basename "$interface")
        
        status=$(cat "$interface/operstate" 2>/dev/null || echo "unknown")
        if [ "$status" = "up" ]; then
            up_interfaces+=("$interface_name")
        elif [ "$status" = "down" ]; then
            down_interfaces+=("$interface_name")
        fi
    done
    
    cat << EOF | sudo tee "$NETPLAN_FILE" > /dev/null
network:
  version: 2
  ethernets:
EOF
    
  for interface in "${up_interfaces[@]}"; do
    echo "    $interface:" | sudo tee -a "$NETPLAN_FILE" > /dev/null
    echo "      dhcp4: true" | sudo tee -a "$NETPLAN_FILE" > /dev/null
    echo "      nameservers:" | sudo tee -a "$NETPLAN_FILE" > /dev/null
    echo "        addresses: [8.8.4.4, 1.0.0.1]" | sudo tee -a "$NETPLAN_FILE" > /dev/null
  done

  for interface in "${down_interfaces[@]}"; do
    echo "    $interface:" | sudo tee -a "$NETPLAN_FILE" > /dev/null
    echo "      dhcp4: true" | sudo tee -a "$NETPLAN_FILE" > /dev/null
    echo "      nameservers:" | sudo tee -a "$NETPLAN_FILE" > /dev/null
    echo "        addresses: [8.8.4.4, 1.0.0.1]" | sudo tee -a "$NETPLAN_FILE" > /dev/null
  done
    
    sudo netplan generate
    sudo netplan apply
}

if ! [ -f /srv/restored1.lock ]; then  
  if [ -f "$pathrestore/docker-network-backup/macvlan.json" ]; then
    cd "$pathrestore/docker-network-backup" || exit
    original_parent="$(jq -r '.[0].Options.parent' macvlan.json)"
    export original_parent
    
    # Verifica se a interface original existe
    if ip link show "$original_parent" >/dev/null 2>&1; then
        clear
        echo "Interface original $original_parent encontrada - usando backup direto!"
        sleep 2
        docker network create -d macvlan \
        --subnet="$(jq -r '.[0].IPAM.Config[0].Subnet' macvlan.json)" \
        --gateway="$(jq -r '.[0].IPAM.Config[0].Gateway' macvlan.json)" \
        -o parent="$original_parent" \
        "$(jq -r '.[0].Name' macvlan.json)"
        
    else
        clear
        echo "Interface $original_parent nao encontrada - configuracao interativa necessaria"
        sleep 3
        auto_configure_netplan
        sleep 3
        if curl -sSL https://raw.githubusercontent.com/urbancompasspony/docker/refs/heads/main/Scripts/macvlan/set | sudo bash; then
            :
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
            sudo systemctl daemon-reload
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
    
    # Restaurar discos pfSense
    echo "📦 Restaurando discos pfSense..."
    find "$pathrestore" -iname "*pfsense*" -type f | while read -r disk_file; do
      file_type=$(file -b "$disk_file")
      if echo "$file_type" | grep -qi "qemu\|disk\|image\|data"; then
        echo "Restaurando disco: $(basename "$disk_file")"
        sudo rsync -aHAXv --numeric-ids --sparse "$disk_file" /var/lib/libvirt/images/
      fi
    done
    
    # Configurar VM pfSense
    echo "🔧 Configurando VM pfSense..."
    
    # Procurar XML pfSense (qualquer variação)
    xml_file=$(find "$pathrestore" -iname "pf*.xml" | head -1)
    
    if [ -n "$xml_file" ]; then
        echo "XML encontrado: $(basename "$xml_file")"
        
        # Função para mapear interfaces
        function map_xml_interfaces {
            local xml_file="$1"
            
            # Detectar interfaces disponíveis no sistema
            available_interfaces=()
            for interface in /sys/class/net/en*; do
                [ -e "$interface" ] || continue
                interface_name=$(basename "$interface")
                available_interfaces+=("$interface_name")
            done
            
            if [ ${#available_interfaces[@]} -eq 0 ]; then
                echo "❌ Nenhuma interface ethernet encontrada"
                return 1
            fi
            
            echo "🔍 Interfaces disponíveis: ${available_interfaces[*]}"
            
            # Extrair interfaces do XML
            xml_interfaces=($(grep -oP "dev='\K[^']*" "$xml_file"))
            
            if [ ${#xml_interfaces[@]} -eq 0 ]; then
                echo "⚠️  Nenhuma interface no XML"
                return 0
            fi
            
            echo "🔍 Interfaces no XML: ${xml_interfaces[*]}"
            
            # Verificar se todas existem
            all_exist=true
            for xml_int in "${xml_interfaces[@]}"; do
                if ! printf '%s\n' "${available_interfaces[@]}" | grep -q "^$xml_int$"; then
                    all_exist=false
                    break
                fi
            done
            
            if [ "$all_exist" = true ]; then
                echo "✅ Todas as interfaces existem - mantendo XML original"
                return 0
            fi
            
            echo "🔄 Mapeando interfaces..."
            cp "$xml_file" "$xml_file.bak"
            
            available_index=0
            for xml_int in "${xml_interfaces[@]}"; do
                # Se existe, manter
                if printf '%s\n' "${available_interfaces[@]}" | grep -q "^$xml_int$"; then
                    echo "  ✓ $xml_int -> $xml_int (mantida)"
                    continue
                fi
                
                # Mapear para próxima disponível
                if [ $available_index -lt ${#available_interfaces[@]} ]; then
                    new_interface="${available_interfaces[$available_index]}"
                    
                    # Pular se já usada no XML
                    while printf '%s\n' "${xml_interfaces[@]}" | grep -q "^$new_interface$"; do
                        ((available_index++))
                        if [ $available_index -ge ${#available_interfaces[@]} ]; then
                            break
                        fi
                        new_interface="${available_interfaces[$available_index]}"
                    done
                    
                    if [ $available_index -lt ${#available_interfaces[@]} ]; then
                        echo "  🔄 $xml_int -> $new_interface"
                        sed -i "0,/dev='$xml_int'/s//dev='$new_interface'/" "$xml_file"
                        ((available_index++))
                    fi
                fi
            done
            
            echo "✅ Mapeamento concluído"
        }
        
        # Executar mapeamento de interfaces
        map_xml_interfaces "$xml_file"
        
        # Definir e iniciar VM
        if virsh define "$xml_file"; then
            echo "✅ VM definida com sucesso"
            
            # Extrair nome real da VM do XML
            vm_name=$(grep -oP '<name>\K[^<]+' "$xml_file")
            echo "Nome da VM: $vm_name"
            
            if virsh start "$vm_name" 2>/dev/null; then
                echo "✅ VM iniciada com sucesso"
            else
                echo "⚠️  Tentando forçar inicialização..."
                virsh start "$vm_name" --force-boot 2>&1 | tee /tmp/vm_start_error.log
                if [ ${PIPESTATUS[0]} -eq 0 ]; then
                    echo "✅ VM iniciada com sucesso (forçada)"
                else
                    echo "❌ Falha ao iniciar VM. Log salvo em /tmp/vm_start_error.log"
                fi
            fi
        else
            echo "❌ Falha ao definir VM"
        fi
    else
        echo "❌ XML pfSense não encontrado em $pathrestore"
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
    ORCHESTRATION_URL="https://raw.githubusercontent.com/urbancompasspony/docker/refs/heads/main/Scripts/orchestration"
    
    # Verificar se containers.yaml existe
    if [ -f /srv/containers.yaml ]; then
        echo "Encontrado containers.yaml, processando containers por img_base..."
        
        # Baixar orchestration apenas se não existir
        if [ ! -f /tmp/orchestration ]; then
            echo "Baixando orchestration..."
            if ! curl -sSL "$ORCHESTRATION_URL" | tee /tmp/orchestration; then
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
