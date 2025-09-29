#!/bin/bash

yamlbase="/srv/system.yaml"
yamlextra="/srv/containers.yaml"

export yamlbase
export yamlextra

LOG_FILE="/var/log/restore-$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "=== Restore iniciado em $(date) ==="
echo "Log salvo em: $LOG_FILE"

function etapa-mount {
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
}

function etapa00-dependencies {
  echo "=== Validando dependências ==="
  
  missing_deps=()
  
  for cmd in yq lz4 jq docker virsh rsync curl; do
    if ! command -v "$cmd" &> /dev/null; then
      missing_deps+=("$cmd")
    fi
  done
  
  if [ ${#missing_deps[@]} -gt 0 ]; then
    clear
    echo ""
    echo "❌ ERRO 08: DEPENDÊNCIAS FALTANDO!"
    echo ""
    echo "Os seguintes pacotes são necessários mas não foram encontrados:"
    printf '   • %s\n' "${missing_deps[@]}"
    echo ""
    echo "Instale-os com:"
    echo "sudo apt install yq liblz4-tool jq docker.io libvirt-clients rsync curl"
    echo ""
    echo "Operação cancelada. Saindo em 10 segundos..."
    sleep 10
    exit 1
  fi
  
  echo "✅ Todas as dependências encontradas"
}

function etapa00-diskspace {
  echo "=== Validando espaço em disco ==="
  
  # Estimar tamanho total dos backups
  backup_size=$(du -sb "$pathrestore" | cut -f1)
  backup_size_gb=$((backup_size / 1024 / 1024 / 1024))
  
  # Espaço disponível em /srv
  available_space=$(df /srv | tail -1 | awk '{print $4}')
  available_gb=$((available_space / 1024 / 1024))
  
  echo "Tamanho do backup: ~${backup_size_gb}GB"
  echo "Espaço disponível: ~${available_gb}GB"
  
  # Precisa de pelo menos 2x o tamanho (descompactação + original)
  required_space=$((backup_size_gb * 2))
  
  if [ $available_gb -lt $required_space ]; then
    clear
    echo ""
    echo "❌ ERRO 09: ESPAÇO INSUFICIENTE!"
    echo ""
    echo "Necessário: ~${required_space}GB"
    echo "Disponível: ~${available_gb}GB"
    echo "Faltam: ~$((required_space - available_gb))GB"
    echo ""
    echo "Libere espaço em /srv antes de continuar."
    echo ""
    echo "Operação cancelada. Saindo em 10 segundos..."
    sleep 10
    exit 1
  fi
  
  echo "✅ Espaço em disco suficiente"
}

function etapa00-github {
  echo "=== Validando conectividade com GitHub ==="
  
  ORCHESTRATION_URL="https://raw.githubusercontent.com/urbancompasspony/docker/refs/heads/main/Scripts/orchestration"
  
  echo "🌐 Testando acesso ao GitHub..."
  
  # Tenta fazer um HEAD request para verificar se o arquivo existe
  if curl -sSf --head --max-time 10 "$ORCHESTRATION_URL" >/dev/null 2>&1; then
    echo "✅ GitHub acessível - orchestration disponível"
    return 0
  else
    clear
    echo ""
    echo "❌ ERRO 07: GITHUB INACESSÍVEL!"
    echo ""
    echo "Não foi possível acessar o GitHub para baixar o orchestration."
    echo ""
    echo "URL testada:"
    echo "$ORCHESTRATION_URL"
    echo ""
    echo "POSSÍVEIS CAUSAS:"
    echo "1. Servidor sem conexão com a internet"
    echo "2. GitHub fora do ar"
    echo "3. Firewall bloqueando acesso"
    echo "4. DNS não está resolvendo corretamente"
    echo ""
    echo "SOLUÇÃO:"
    echo "- Verifique a conexão de internet: ping 8.8.8.8"
    echo "- Teste o DNS: nslookup raw.githubusercontent.com"
    echo "- Verifique firewall/proxy"
    echo "- Aguarde se GitHub estiver indisponível"
    echo ""
    echo "O restore NÃO pode continuar sem acesso ao orchestration!"
    echo ""
    echo "Operação cancelada. Saindo em 10 segundos..."
    sleep 10
    exit 1
  fi
}

function restorefunc {
  pathrestore=$(find /mnt/bkpsys -name "*.tar.lz4" 2>/dev/null | head -1 | xargs dirname)
  if [ -z "$pathrestore" ]; then
    echo "ERRO: Nenhum backup encontrado em /mnt/bkpsys"
    exit 1
  fi
  export pathrestore
}

function etapa00-restored {
  if [ -f /srv/restored8.lock ]; then
    clear
    echo ""
    echo "ERRO 01: ⏭ ESTE SERVIDOR JÁ FOI RESTAURADO COMPLETAMENTE! (lock existe)"
    echo "Se o sistema apresenta falhas nos serviços, recomendo que formate e refaça o sistema restaurando novamente."
    echo "Operacao cancelada. Saindo em 5 segundos..."
    sleep 5
    exit 1
  fi
}

function etapa00-machineid {
  if [ -f "$pathrestore"/system.yaml ]; then
    CURRENT_MACHINE_ID=$(cat /etc/machine-id 2>/dev/null)
    BACKUP_MACHINE_ID=$(yq -r '.Informacoes.machine_id' "$pathrestore"/system.yaml 2>/dev/null)
    if [ -z "$BACKUP_MACHINE_ID" ] || [ "$BACKUP_MACHINE_ID" = "null" ]; then
      clear
      echo ""
      echo "ERRO 03: VALIDACAO!"
      echo "O machine-id no backup esta nulo ou invalido."
      echo "Operacao cancelada. Saindo em 5 segundos..."
      sleep 5
      exit 1
    fi
    if [ "$CURRENT_MACHINE_ID" = "$BACKUP_MACHINE_ID" ]; then
      clear
      echo ""
      echo "ERRO 04: machine-id igual encontrado neste servidor!"
      echo "Entendemos que esta forcando a restauracao em um sistema em plena execucao normal."
      echo "Para restaurar, reexecute essa restauracao em outro sistema limpo ou formate o atual."
      echo "Operacao cancelada. Saindo em 5 segundos..."
      sleep 5
      exit 1
    fi
  else
    clear
    echo ""
    echo "ERRO 02: Arquivo system.yaml nao encontrado no backup!"
    echo "Nao e possivel validar este backup encontrado."
    echo "Operacao cancelada. Saindo em 5 segundos..."
    sleep 5
    exit 1
  fi
}

function etapa00-hostname {
  if [ "$(hostname)" = "ubuntu-server" ]; then
    :;
  else
    clear
    echo ""; echo ""
    echo "ERRO 05: Este sistema ja esta com o hostname $(hostname)."
    echo "Entendemos talvez este seja um sistema legitimo que nao pode ser sobrescrito."
    echo "Se voce realmente quer restaurar o servidor aqui, renomeie este sistema para o hostname 'ubuntu-server' e tente reexecutar este utilitario!"
    echo "Operacao cancelada. Saindo em 5 segundos..."
    sleep 5
    exit 1
  fi
}

function etapa00-interfaces {
  echo "=== Validando interfaces de rede para pfSense ==="
  
  # Procurar XML do pfSense no backup
  xml_file=$(find "$pathrestore" -iname "pf*.xml" 2>/dev/null | head -1)
  
  if [ -z "$xml_file" ]; then
    echo "⚠️  Nenhum XML de pfSense encontrado no backup"
    echo "✓ Validação de interfaces: PULADA (sem VM para restaurar)"
    return 0
  fi
  
  echo "📄 XML encontrado: $(basename "$xml_file")"
  
  # Detectar interface do Docker (será ignorada)
  docker_interface=$(yq -r '.[0].Options.parent' "$pathrestore"/docker-network-backup/macvlan.json 2>/dev/null)
  
  if [ -z "$docker_interface" ] || [ "$docker_interface" = "null" ]; then
    echo "⚠️  Não foi possível detectar interface Docker do backup"
    echo "   Assumindo que será criada durante restore"
    docker_interface="NONE"
  else
    echo "🐳 Interface Docker no backup: $docker_interface (será ignorada)"
  fi
  
  # Extrair interfaces do XML, excluindo a do Docker
  mapfile -t xml_interfaces < <(grep -oP "dev='\K[^']*" "$xml_file" | grep -v "^$docker_interface$" | sort -u)
  
  if [ ${#xml_interfaces[@]} -eq 0 ]; then
    echo "✓ Validação de interfaces: OK (nenhuma interface no XML)"
    return 0
  fi
  
  echo "🔍 Interfaces necessárias no XML (exceto Docker):"
  printf '   • %s\n' "${xml_interfaces[@]}"
  echo "   Total: ${#xml_interfaces[@]} interface(s)"
  echo ""
  
  # Detectar interfaces físicas disponíveis no sistema atual
  available_interfaces=()
  for interface in /sys/class/net/*; do
    [ -e "$interface" ] || continue
    interface_name=$(basename "$interface")
    
    # Pular loopback, docker e interfaces virtuais
    [[ "$interface_name" == "lo" ]] && continue
    [[ "$interface_name" == docker* ]] && continue
    [[ "$interface_name" == br-* ]] && continue
    [[ "$interface_name" == veth* ]] && continue
    [[ "$interface_name" == virbr* ]] && continue
    [[ "$interface_name" == tap* ]] && continue
    
    # Aceitar apenas interfaces físicas ethernet
    if [[ "$interface_name" =~ ^(en|em|eth|eno|enp|ens) ]]; then
      # Verificar se está UP ou pode ser ativada
      if ip link show "$interface_name" >/dev/null 2>&1; then
        available_interfaces+=("$interface_name")
      fi
    fi
  done
  
  if [ ${#available_interfaces[@]} -eq 0 ]; then
    clear
    echo ""
    echo "❌ ERRO 06: INTERFACES INSUFICIENTES!"
    echo ""
    echo "O backup contém uma VM pfSense que requer ${#xml_interfaces[@]} interface(s) ethernet:"
    printf '   • %s\n' "${xml_interfaces[@]}"
    echo ""
    echo "Porém, este sistema NÃO possui nenhuma interface ethernet física disponível!"
    echo ""
    echo "Interfaces detectadas no sistema:"
    for iface in /sys/class/net/*; do
      [ -e "$iface" ] && echo "   • $(basename "$iface")"
    done
    echo ""
    echo "SOLUÇÃO:"
    echo "1. Adicione placas de rede físicas ao servidor"
    echo "2. Ou remova a VM pfSense do backup antes de restaurar"
    echo ""
    echo "Operação cancelada. Saindo em 10 segundos..."
    sleep 10
    exit 1
  fi
  
  echo "🌐 Interfaces ethernet disponíveis neste sistema:"
  printf '   • %s\n' "${available_interfaces[@]}"
  echo "   Total: ${#available_interfaces[@]} interface(s)"
  echo ""
  
  # VERIFICAÇÃO CRÍTICA: Comparar quantidade
  if [ ${#xml_interfaces[@]} -gt ${#available_interfaces[@]} ]; then
    clear
    echo ""
    echo "❌ ERRO 06: INTERFACES INSUFICIENTES!"
    echo ""
    echo "┌─────────────────────────────────────────────────┐"
    echo "│  O backup requer:  ${#xml_interfaces[@]} interface(s) ethernet      │"
    echo "│  Sistema possui:   ${#available_interfaces[@]} interface(s) disponível(is) │"
    echo "└─────────────────────────────────────────────────┘"
    echo ""
    echo "Interfaces necessárias (do backup):"
    printf '   • %s\n' "${xml_interfaces[@]}"
    echo ""
    echo "Interfaces disponíveis (neste sistema):"
    printf '   • %s\n' "${available_interfaces[@]}"
    echo ""
    echo "A VM pfSense NÃO poderá ser restaurada corretamente!"
    echo ""
    echo "SOLUÇÕES POSSÍVEIS:"
    echo "1. Adicione mais $(( ${#xml_interfaces[@]} - ${#available_interfaces[@]} )) placa(s) de rede física ao servidor"
    echo "2. Edite o XML do pfSense no backup para usar menos interfaces"
    echo "3. Continue o restore, mas a VM pfSense ficará inoperante"
    echo ""
    echo "Deseja continuar mesmo assim? A VM NÃO será iniciada."
    
    read -p "Digite 'sim' para continuar ou pressione ENTER para cancelar: " resposta
    resposta=$(echo "$resposta" | tr '[:upper:]' '[:lower:]' | xargs)
    if [ "$resposta" = "sim" ]; then
      echo ""
      echo "⚠️  Continuando restore... VM pfSense será definida mas NÃO iniciada"
      sleep 3
      return 0
    else
      echo ""
      echo "Operação cancelada pelo usuário. Saindo em 5 segundos..."
      sleep 5
      exit 1
    fi
  fi
  
  echo "✅ Validação de interfaces: OK"
  echo "   Sistema possui interfaces suficientes para restaurar pfSense"
  sleep 2
}

function etapa00-ok {
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
}

function etapa01 {
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
}

function etapa02 {
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
}

# ============================================
# FUNÇÃO AUXILIAR PARA MAPEAMENTO DE INTERFACES
# Deve estar FORA de etapa03 para evitar problemas de escopo
# ============================================
function map_xml_interfaces {
    local xml_file="$1"
    local original_parent="$2"
    
    # Detectar interfaces disponíveis no sistema (excluindo loopback e docker)
    available_interfaces=()
    for interface in /sys/class/net/*; do
        [ -e "$interface" ] || continue
        interface_name=$(basename "$interface")

        # Pular loopback, docker e interfaces virtuais
        [[ "$interface_name" == "lo" ]] && continue
        [[ "$interface_name" == docker* ]] && continue
        [[ "$interface_name" == br-* ]] && continue
        [[ "$interface_name" == veth* ]] && continue

        # Aceitar apenas interfaces físicas ethernet
        if [[ "$interface_name" =~ ^(en|em|eth|eno|enp|ens) ]]; then
            available_interfaces+=("$interface_name")
        fi
    done

    if [ ${#available_interfaces[@]} -eq 0 ]; then
        echo "❌ Nenhuma interface ethernet encontrada"
        return 1
    fi

    # Extrair interfaces APENAS de blocos <interface type='direct'>
    # Procura por <source dev='...' mode='bridge'/> dentro de <interface type='direct'>
    xml_interfaces=($(grep -Pzo "(?s)<interface type='direct'>.*?</interface>" "$xml_file" | \
                  grep -Po "dev='\K[^']*" | \
                  grep -v "^$original_parent$" | \
                  sort -u))
    
    if [ ${#xml_interfaces[@]} -eq 0 ]; then
        echo "⚠️  Nenhuma interface no XML"
        return 0
    fi

    # Se XML tem mais interfaces que o sistema
    if [ ${#xml_interfaces[@]} -gt ${#available_interfaces[@]} ]; then
        echo "⚠️  XML requer ${#xml_interfaces[@]} interfaces, mas sistema só tem ${#available_interfaces[@]}"
        echo "⏭  Pulando mapeamento e inicialização da VM - interfaces insuficientes"
        return 2
    fi

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
}

function etapa03 {
  if ! [ -f /srv/restored3.lock ]; then
      echo "=== ETAPA 3: Restaurando VMs pfSense ==="

      # Restaurar discos pfSense
      find "$pathrestore" -iname "*pfsense*" -type f | while read -r disk_file; do
        file_type=$(file -b "$disk_file")
        if echo "$file_type" | grep -qi "qemu\|disk\|image\|data"; then
          echo "Restaurando disco: $(basename "$disk_file")"
          sudo rsync -aHAXv --numeric-ids --sparse "$disk_file" /var/lib/libvirt/images/
        fi
      done

      # Procurar XML pfSense (qualquer variação)
      xml_file=$(find "$pathrestore" -iname "pf*.xml" | head -1)

      if [ -n "$xml_file" ]; then
          echo "XML encontrado: $(basename "$xml_file")"
          
          # Interface do Docker para ser ignorada e não usada no pfSense
          docker_interface=$(docker network inspect macvlan 2>/dev/null | jq -r '.[0].Options.parent' 2>/dev/null)
          original_parent="$docker_interface"

          if [ -z "$original_parent" ] || [ "$original_parent" = "null" ]; then
            echo "ERRO: Rede macvlan não encontrada. Execute etapa01 primeiro ou crie a rede manualmente."
            sleep 3
            return 1
          fi

          # Executar mapeamento de interfaces (agora passando parâmetros explicitamente)
          map_xml_interfaces "$xml_file" "$original_parent"
          mapping_result=$?

          # Só definir e iniciar VM se o mapeamento foi bem-sucedido
          if [ $mapping_result -eq 2 ]; then
              echo "⏭  VM não será iniciada devido à falta de interfaces"
          elif virsh define "$xml_file"; then
              # Extrair nome real da VM do XML
              vm_name=$(grep -oP '<name>\K[^<]+' "$xml_file")
              
              if [ -z "$vm_name" ]; then
                  echo "❌ Não foi possível extrair o nome da VM do XML"
              else
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
              fi
          else
              echo "❌ Falha ao definir VM"
          fi
      fi

      sudo touch /srv/restored3.lock
      echo "✅ ETAPA 3 concluída"
  else
      echo "⏭ ETAPA 3 já executada (lock existe)"
  fi
}

function etapa04 {
  if ! [ -f /srv/restored4.lock ]; then
      echo "=== ETAPA 4: Restaurando containers (mais recente de cada) ==="

      # Criar diretório se não existir
      sudo mkdir -p /srv/containers

      # Restaurar YAMLs
      if [ -f "$pathrestore/system.yaml" ];then
        sudo rsync -aHAXv --numeric-ids --sparse "$pathrestore/system.yaml" /srv/
      else
        clear; echo "ERROR: Nao encontrei o system.yaml. SAINDO..."
        exit 1
      fi

      if [ -f "$pathrestore/containers.yaml" ]; then
        sudo rsync -aHAXv --numeric-ids --sparse "$pathrestore/containers.yaml" /srv/
      else
        clear
        echo "WARNING: Nao encontrei o containers.yaml. Vou criar um YAML vazio e prosseguir."
        echo "Verifique se isso esta correto pois sem o YAML nenhum container ira inicializar."
        sleep 5
        sudo touch /srv/containers.yaml
      fi

      echo "🔍 Analisando arquivos de container..."

      # Encontrar todos os arquivos .tar.lz4 (exceto etc)
      # Usar sort -V para ordenação natural de versão
      temp_file="/tmp/container_analysis.$$"
      find "$pathrestore" -name "*.tar.lz4" -not -name "etc*.tar.lz4" -printf '%f\n' | sort -V > "$temp_file"

      # Extrair nomes base únicos e pegar o mais recente de cada
      declare -A latest_files

      while read -r filename; do
          # Extrair nome base (tudo antes da data)
          # Ex: openspeedtest-29_09_25.tar.lz4 -> openspeedtest
          basename_clean=$(echo "$filename" | sed 's/-[0-9][0-9]_[0-9][0-9]_[0-9][0-9]\.tar\.lz4$//')

          # Como está ordenado por sort -V, sempre substitui com o mais recente
          latest_files[$basename_clean]="$filename"
      done < "$temp_file"

      rm -f "$temp_file"

      # Restaurar os arquivos selecionados
      if [ ${#latest_files[@]} -gt 0 ]; then
          echo "📦 Encontrados ${#latest_files[@]} containers únicos:"

          for basename_clean in "${!latest_files[@]}"; do
              filename="${latest_files[$basename_clean]}"
              filepath="$pathrestore/$filename"
              
              echo "  - $basename_clean: $filename"

              if [ -f "$filepath" ]; then
                  echo "    Extraindo: $filename"
                  if sudo tar -I 'lz4 -d -c' -xf "$filepath" -C /srv/containers 2>/dev/null; then
                      echo "    ✅ Extraído com sucesso"
                  else
                      echo "    ❌ ERRO ao extrair - arquivo pode estar corrompido!"
                      continue
                  fi
              else
                  echo "    ⚠️  Arquivo não encontrado: $filepath"
              fi
          done

          echo "✅ Containers restaurados (mais recente de cada)"
      else
          echo "❌ Nenhum arquivo de container encontrado!"
      fi

      sudo touch /srv/restored4.lock
      echo "✓ ETAPA 4 concluída"
  else
      echo "⏭ ETAPA 4 já executada (lock existe)"
  fi
}

function etapa05 {
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

          # Lógica: Pegar a img_base e repassar como nome-do-script-no-GitHub
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
          rm -f /srv/lockfile
          
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
                  rm -f /srv/lockfile
                  
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
}

function etapa06 {
  if ! [ -f /srv/restored6.lock ]; then
    sudo crontab "$pathrestore"/crontab-bkp
    sudo touch /srv/restored6.lock
    echo "✓ ETAPA 6 concluída"
  else
    echo "⏭ ETAPA 6 já executada (lock existe)"
  fi
}

function etapa07 {
  datetime0=$(date +"%d/%m/%Y - %H:%M")
  sudo yq -i ".Informacoes.Data_Ultima_Reinstalacao = \"${datetime0}\"" "$yamlbase"
  echo "=== RESTORE COMPLETO ==="
  sleep 3
  echo "Reiniciando..."
  sudo touch /srv/restored7.lock
  sleep 3
  sudo reboot
}

etapa-mount
etapa00-dependencies
etapa00-diskspace
etapa00-github
etapa00-restored
etapa00-machineid
etapa00-hostname
etapa00-interfaces
etapa00-ok

etapa01
etapa02
etapa03
etapa04
etapa05
etapa06
etapa07

exit 0
