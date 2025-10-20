#!/bin/bash

yamlbase="/srv/system.yaml"
yamlextra="/srv/containers.yaml"

export yamlbase
export yamlextra

rede00="1"
export rede00

LOG_FILE="/var/log/restore-total-1-$(date +%Y%m%d_%H%M%S).log"
exec 1> >(sudo tee -a "$LOG_FILE")
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

function restorefunc {
  pathrestore=$(find /mnt/bkpsys -name "*.tar.lz4" 2>/dev/null | head -1 | xargs dirname)
  if [ -z "$pathrestore" ]; then
    echo "ERRO: Nenhum backup encontrado em /mnt/bkpsys"
    exit 1
  fi
  export pathrestore
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

function etapa00-restored {
  if [ -f /srv/restored7.lock ]; then
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
  mapfile -t xml_interfaces < <(awk '/<interface type=.direct.>/,/<\/interface>/ {if ($0 ~ /dev=/) print}' "$xml_file" | \
    grep -oP "dev='\K[^']*" | \
    grep -v "^$docker_interface$" | \
    sort -u)
                              
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
    
    read -r -t 60 -p "Digite 'sim' para continuar ou pressione ENTER para cancelar: " resposta || resposta="sim"
    
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
  if ! [ -f /srv/restored1.lock ]; then
    if [ -f "$pathrestore/docker-network-backup/macvlan.json" ]; then
      cd "$pathrestore/docker-network-backup" || exit
      
      # Ler configurações do backup
      original_parent="$(jq -r '.[0].Options.parent' macvlan.json)"
      network_name="$(jq -r '.[0].Name' macvlan.json)"
      subnet="$(jq -r '.[0].IPAM.Config[0].Subnet' macvlan.json)"
      gateway="$(jq -r '.[0].IPAM.Config[0].Gateway' macvlan.json)"
      
      echo "=== ETAPA 1: Configurando rede Docker macvlan ==="
      echo "Configurações do backup:"
      echo "  Nome: $network_name"
      echo "  Subnet: $subnet"
      echo "  Gateway: $gateway"
      echo "  Interface original: $original_parent"
      echo ""
      
      # Verificar se a interface original existe
      if ip link show "$original_parent" >/dev/null 2>&1; then
          clear
          echo "✅ Interface original $original_parent encontrada!"
          echo ""
          echo "Criando rede macvlan com configurações do backup..."
          sleep 2
          
          if docker network create -d macvlan \
            --subnet="$subnet" \
            --gateway="$gateway" \
            -o parent="$original_parent" \
            "$network_name"; then
            
            echo "✅ Rede macvlan criada com sucesso!"
            export original_parent
            
            rede00="0"
            export rede00
            
          else
            echo "❌ ERRO ao criar rede macvlan"
            echo ""
            echo "Possíveis causas:"
            echo "  - Rede já existe (verificar: docker network ls)"
            echo "  - Conflito de subnet"
            echo "  - Interface em uso"
            echo ""
            sleep 5
            exit 1
          fi
          
      else
          clear
          echo "⚠️ Interface $original_parent não encontrada no sistema!"
          echo ""
          echo "📋 Interfaces ethernet disponíveis:"
          echo ""
          
          # Listar interfaces disponíveis
          for interface in /sys/class/net/*; do
            [ -e "$interface" ] || continue
            interface_name=$(basename "$interface")
            
            # Mostrar apenas interfaces físicas ethernet
            if [[ "$interface_name" =~ ^(en|em|eth|eno|enp|ens) ]]; then
              # Pegar IP se tiver
              ip_addr=$(ip -4 addr show "$interface_name" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
              if [ -n "$ip_addr" ]; then
                echo "  • $interface_name (IP: $ip_addr)"
              else
                echo "  • $interface_name (sem IP)"
              fi
            fi
          done
          
          echo ""
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "⚠️  ATENÇÃO: Configuração de Rede Docker"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo ""
          echo "A rede será criada com as seguintes configurações do backup:"
          echo ""
          echo "  Nome da rede: $network_name"
          echo "  Subnet:       $subnet"
          echo "  Gateway:      $gateway"
          echo ""
          echo "⚠️  IMPORTANTE: Escolha a interface que está conectada"
          echo "    na mesma LAN do pfSense para os containers!"
          echo ""
          
          interface_list=""
          for interface in /sys/class/net/*; do
            [ -e "$interface" ] || continue
            interface_name=$(basename "$interface")
  
            # Mostrar apenas interfaces físicas ethernet
            if [[ "$interface_name" =~ ^(en|em|eth|eno|enp|ens) ]]; then
              # Pegar IP se tiver
              ip_addr=$(ip -4 addr show "$interface_name" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
             if [ -n "$ip_addr" ]; then
                interface_list+="  • $interface_name (IP: $ip_addr)\n"
              else
                interface_list+="  • $interface_name (sem IP)\n"
              fi
            fi
          done

          # Dialog interativo com lista dinâmica
          if ! new_parent=$(dialog --stdout --title "Interface de Rede para os Containers" \
            --backtitle "Restauração - Etapa 1" \
            --inputbox "\nDigite o nome da interface ethernet que será usada\npara a rede macvlan dos containers.\n\nEsta interface será a mesma LAN do Host Linux (não a LAN do pfSense)!\n\nInterfaces disponíveis:\n\n${interface_list}\nInterface:" \
            22 70) || [ -z "$new_parent" ]; then
            clear
            echo "❌ Operação cancelada pelo usuário"
            echo "Não é possível continuar sem configurar a rede Docker"
            exit 1
          fi
          
          # Validar se a interface existe
          if ! ip link show "$new_parent" >/dev/null 2>&1; then
            clear
            echo "❌ ERRO: Interface '$new_parent' não existe no sistema!"
            echo ""
            echo "Interfaces disponíveis:"
            ip -o link show | awk -F': ' '{print "  • " $2}'
            echo ""
            echo "Execute o restore novamente e escolha uma interface válida."
            sleep 5
            exit 1
          fi
          
          clear
          echo "✅ Interface selecionada: $new_parent"
          echo ""
          echo "Criando rede macvlan com configurações do backup..."
          echo "  Nome: $network_name"
          echo "  Subnet: $subnet"
          echo "  Gateway: $gateway"
          echo "  Interface: $new_parent"
          echo ""
          sleep 2
          
          # Criar rede com a nova interface
          if docker network create -d macvlan \
            --subnet="$subnet" \
            --gateway="$gateway" \
            -o parent="$new_parent" \
            "$network_name"; then
            
            echo "✅ Rede macvlan criada com sucesso!"
            original_parent="$new_parent"
            export original_parent
            
          else
            echo "❌ ERRO ao criar rede macvlan"
            echo ""
            echo "Possíveis causas:"
            echo "  - Rede já existe"
            echo "  - Conflito de subnet com a rede atual"
            echo "  - Interface em uso por outra aplicação"
            echo ""
            sleep 5
            exit 1
          fi
      fi
      
      # Salvar configuração final no system.yaml
      if [ -f /srv/system.yaml ]; then
          echo ""
          echo "💾 Salvando configuração no system.yaml..."
          sudo yq -i ".Rede.interface_docker = \"$original_parent\"" /srv/system.yaml
          sudo yq -i ".Rede.subnet = \"$subnet\"" /srv/system.yaml
          sudo yq -i ".Rede.gateway = \"$gateway\"" /srv/system.yaml
          echo "✓ Configuração salva"
      else
          echo "⚠️ system.yaml ainda não existe - será salvo na etapa04"
      fi
      
      sudo touch /srv/restored1.lock
      echo ""
      echo "✅ ETAPA 1 concluída"
      sleep 2
      
    else
      echo "⚠️ Arquivo macvlan.json não encontrado no backup"
      echo "Pulando configuração de rede Docker"
    fi
  else
    echo "⏭ ETAPA 1 já executada (lock existe)"
  fi
}

function etapa01 {
  VALUE0=$(dialog --ok-label "Restaurar?" --title "Prepare-se" --backtitle "Este Sistema Passou em Todos os Testes Iniciais - Backup encontrado e condições satisfeitas." --form "\nPOR FAVOR CONFIRME QUE VOCE ESTA DE ACORDO \nCOM OS RISCOS INERENTES A ESTA RESTAURACAO! \n\n
PODEM HAVER PERDA DE DADOS SENSIVEIS \nOU DANOS AO SISTEMA OPERACIONAL \nSE FIZER ESTA OPERAÇÃO DESNECESSSARIAMENTE.\n\nRepita no campo abaixo: \neu estou ciente dos riscos" 0 0 0 \
"." 1 1 "$VALUE1" 1 1 45 0 3>&1 1>&2 2>&3 3>&- > /dev/tty)
    case $? in
      0) : ;;
      1) return ;;
    esac
    var1=$(echo "$VALUE0" | sed -n 1p)
    if [ "$var1" = "eu estou ciente dos riscos" ]; then
      clear; echo "ESTA TUDO CORRETO! TUDO FOI DEVIDAMENTE VALIDADO."; sleep 1
      echo "5"; echo "O SERVIDOR SERÁ COMPLETAMENTE RESTAURADO BASEADO NO BACKUP ENCONTRADO!"; sleep 1
      echo "4"; echo "NÃO INTERAJA COM ABSOLUTAMENTE NADA, A MENOS QUE DEVIDAMENTE SOLICITADO!"; sleep 1
      echo "3"; echo "SE QUISER DESISTIR AGORA, PRESSIONE: CTRL + C"; sleep 1
      echo "2"; echo "NÃO DESLIGUE O SERVIDOR DA TOMADA ATÉ O MOMENTO DO REINÍCIO AUTOMÁTICO."; sleep 1
      echo "1"; echo "Que a boa sorte lhe acompanhe nesta restauração!"
      sleep 3
      clear
    else
      clear; echo ""; echo "Por favor repita a frase exatamente como pedi! Saindo..."
      exit 1
    fi
}

function etapa02 {
  if ! [ -f /srv/restored2.lock ]; then
      echo "=== ETAPA 2: Restaurando /etc ==="

      # Encontrar arquivo etc mais recente
      etc_file=$(find "$pathrestore" -name "etc-*.tar.lz4" | sort | tail -1)

      if [ -n "$etc_file" ]; then
          echo "1. Restaurando /etc completo (exceto fstab)..."
          sudo tar -I 'lz4 -d -c' -xpf "$etc_file" -C / \
            --exclude='etc/netplan' \
            --exclude='etc/apt'

          echo "1.1 Atualizando configuração do GRUB..."
          if [ -f /etc/default/grub ]; then
              if sudo update-grub2 2>/dev/null; then
                  echo "✓ GRUB2 atualizado"
              else
                  echo "⚠️ Erro ao atualizar GRUB2 (pode não estar instalado)"
              fi
          else
              echo "⚠️ /etc/default/grub não encontrado"
          fi

          echo "2. Procurando backup do fstab..."
          fstab_backup=$(find "$pathrestore" -name "fstab.backup" | sort | tail -1)

          if [ -n "$fstab_backup" ]; then
              echo "Encontrado: $(basename "$fstab_backup")"
              echo "3. Fazendo backup do fstab atual..."
              sudo cp /etc/fstab "/etc/fstab.bkp-preventivo.$(date +%Y%m%d_%H%M%S)"

              echo "4. Aplicando merge inteligente do fstab com validação..."
              
              # Criar arquivo temporário para processar
              temp_fstab="/tmp/fstab.merge.$$"
              
              # Processar cada linha do backup
              while IFS= read -r line; do
                  # Pular comentários e linhas vazias
                  if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
                      continue
                  fi
                  
                  # Extrair o device/UUID (primeiro campo)
                  device=$(echo "$line" | awk '{print $1}')
                  mountpoint=$(echo "$line" | awk '{print $2}')
                  
                  # Pular se já existe no fstab atual
                  if grep -q "^[^#]*[[:space:]]${mountpoint}[[:space:]]" /etc/fstab; then
                      echo "  ⏭ Pulando $mountpoint (já existe no fstab atual)"
                      continue
                  fi
                  
                  # Verificar se é UUID ou device path
                  device_exists=false
                  
                  if [[ "$device" =~ ^UUID= ]]; then
                      # Extrair UUID
                      uuid="${device#UUID=}"
                      
                      # Verificar se o UUID existe
                      if blkid | grep -qi "$uuid"; then
                          device_exists=true
                          echo "  ✓ UUID encontrado: $uuid -> $mountpoint"
                      else
                          echo "  ✗ UUID não encontrado: $uuid -> $mountpoint"
                      fi
                      
                  elif [[ "$device" =~ ^LABEL= ]]; then
                      # Extrair LABEL
                      label="${device#LABEL=}"
                      
                      # Verificar se o LABEL existe
                      if blkid | grep -qi "LABEL=\"$label\""; then
                          device_exists=true
                          echo "  ✓ LABEL encontrado: $label -> $mountpoint"
                      else
                          echo "  ✗ LABEL não encontrado: $label -> $mountpoint"
                      fi
                      
                  elif [[ "$device" =~ ^/dev/ ]]; then
                      # Device path direto
                      if [ -b "$device" ]; then
                          device_exists=true
                          echo "  ✓ Device encontrado: $device -> $mountpoint"
                      else
                          echo "  ✗ Device não encontrado: $device -> $mountpoint"
                      fi
                  else
                      # Outros tipos (nfs, tmpfs, etc) - assume que existem
                      device_exists=true
                      echo "  ℹ Tipo especial: $device -> $mountpoint"
                  fi
                  
                  # Adicionar nofail se device não existe
                  if [ "$device_exists" = false ]; then
                      # Verificar se já tem nofail
                      if [[ "$line" =~ nofail ]]; then
                          echo "$line" >> "$temp_fstab"
                          echo "    → Adicionando com nofail (já presente)"
                      else
                          # Adicionar nofail na coluna de opções (4ª coluna)
                          modified_line=$(echo "$line" | awk '{
                              if (NF >= 4) {
                                  $4 = $4 ",nofail"
                              } else {
                                  $4 = "defaults,nofail"
                              }
                              print $0
                          }')
                          echo "$modified_line" >> "$temp_fstab"
                          echo "    → Adicionando com nofail (ADICIONADO)"
                      fi
                  else
                      echo "$line" >> "$temp_fstab"
                      echo "    → Adicionando normalmente"
                  fi
                  
              done < "$fstab_backup"
              
              # Adicionar linhas validadas ao fstab atual
              if [ -f "$temp_fstab" ]; then
                  #sudo tee -a /etc/fstab < "$temp_fstab" > /dev/null
                  cat "$temp_fstab" | sudo tee -a /etc/fstab > /dev/null
                  rm -f "$temp_fstab"
              fi

              echo "5. Testando configuração..."
              sudo systemctl daemon-reload
              if sudo mount -a --fake; then
                  echo "✓ fstab válido"
              else
                  echo "✗ Erro no fstab! Restaurando backup..."
                  sudo cp "/etc/fstab.bkp-preventivo."* /etc/fstab 2>/dev/null || true
              fi
          else
              echo "⚠ Nenhum backup de fstab encontrado em $pathrestore"
          fi

          # Limpeza de comentários e linhas vazias
          sudo sed -i '/^[[:space:]]*#/d; /^[[:space:]]*$/d; s/[[:space:]]*$//' /etc/fstab

          sudo touch /srv/restored2.lock
          echo "✓ ETAPA 2 concluída"
      else
          echo "❌ Nenhum arquivo etc-*.tar.lz4 encontrado em $pathrestore"
      fi
  else
      echo "⏭ ETAPA 2 já executada (lock existe)"
  fi
}

function map_xml_interfaces {
    local xml_file="$1"
    local original_parent="$2"
    
    echo "=== Mapeamento de Interfaces da VM ==="
    echo "Arquivo XML: $xml_file"
    echo "Interface Docker (ignorada): $original_parent"
    echo ""
    
    # Detectar interfaces disponíveis no sistema
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
            available_interfaces+=("$interface_name")
        fi
    done

    if [ ${#available_interfaces[@]} -eq 0 ]; then
        echo "❌ Nenhuma interface ethernet encontrada no sistema"
        return 1
    fi

    echo "🌐 Interfaces ethernet disponíveis no sistema:"
    printf '   • %s\n' "${available_interfaces[@]}"
    echo ""

    # Extrair TODAS as linhas que contêm dev='' dentro de interface type='direct'
    mapfile -t xml_interfaces < <(awk '/<interface type=.direct.>/,/<\/interface>/ {if ($0 ~ /dev=/) print}' "$xml_file" | \
      grep -oP "dev='\K[^']*" | \
      grep -v "^$original_parent$" | \
      sort -u)
    
    if [ ${#xml_interfaces[@]} -eq 0 ]; then
        echo "⚠️  Nenhuma interface de rede no XML (apenas Docker)"
        return 0
    fi

    echo "📋 Interfaces no XML do backup:"
    printf '   • %s\n' "${xml_interfaces[@]}"
    echo ""

    # VALIDAÇÃO: Verificar quantidade
    if [ ${#xml_interfaces[@]} -gt ${#available_interfaces[@]} ]; then
        echo "❌ XML requer ${#xml_interfaces[@]} interface(s), sistema tem ${#available_interfaces[@]}"
        echo "⏭  VM será definida mas NÃO iniciada"
        return 2
    fi

    # Verificar quais interfaces do XML existem no sistema
    missing_interfaces=()
    existing_interfaces=()
    
    for xml_int in "${xml_interfaces[@]}"; do
        if printf '%s\n' "${available_interfaces[@]}" | grep -q "^$xml_int$"; then
            existing_interfaces+=("$xml_int")
        else
            missing_interfaces+=("$xml_int")
        fi
    done

    # SE TODAS EXISTEM: não precisa mapear
    if [ ${#missing_interfaces[@]} -eq 0 ]; then
        echo "✅ Todas as interfaces do XML existem no sistema"
        printf '   ✓ %s\n' "${existing_interfaces[@]}"
        echo "📝 Nenhuma modificação necessária - usando XML original"
        return 0
    fi

    # PRECISA MAPEAR
    echo "⚠️  Interfaces que NÃO existem no sistema:"
    printf '   ✗ %s\n' "${missing_interfaces[@]}"
    echo ""
    echo "🔧 Iniciando mapeamento automático..."
    echo ""

    # Backup do XML original
    if [ ! -f "$xml_file.original" ]; then
        cp "$xml_file" "$xml_file.original"
        echo "💾 Backup: $xml_file.original"
    fi

    # Interfaces disponíveis para mapeamento (não usadas no XML)
    available_for_mapping=()
    for avail_int in "${available_interfaces[@]}"; do
        # Pular se for a interface do Docker
        if [ "$avail_int" = "$original_parent" ]; then
            continue
        fi
        # Pular se já está sendo usada no XML
        if ! printf '%s\n' "${existing_interfaces[@]}" | grep -q "^$avail_int$"; then
            available_for_mapping+=("$avail_int")
        fi
    done

    # VALIDAÇÃO: Verifica se há interfaces disponíveis
    if [ ${#available_for_mapping[@]} -eq 0 ]; then
        clear
        echo ""
        echo "⚠️  AVISO: Mapeamento de Interfaces Impossível"
        echo ""
        echo "╔════════════════════════════════════════════════════╗"
        echo "║  A interface do Docker é a única disponível!      ║"
        echo "║  O pfSense NÃO poderá ser iniciado automaticamente║"
        echo "╚════════════════════════════════════════════════════╝"
        echo ""
        echo "Interfaces necessárias pelo pfSense:"
        printf '   • %s\n' "${xml_interfaces[@]}"
        echo ""
        echo "Interface reservada para Docker:"
        echo "   • $original_parent (BLOQUEADA)"
        echo ""
        echo "O QUE VAI ACONTECER:"
        echo "  ✓ VM será definida no libvirt"
        echo "  ✗ VM NÃO será iniciada (faltam interfaces)"
        echo "  ✓ XML ficará preparado em /tmp/pfsense-restore.xml"
        echo ""
        echo "INTERVENÇÃO MANUAL NECESSÁRIA:"
        echo "  1. Adicione mais placa(s) de rede física"
        echo "  2. Edite o XML: virsh edit pfsense"
        echo "  3. Mapeie as interfaces manualmente"
        echo "  4. Inicie a VM: virsh start pfsense"
        echo ""
        echo "Continuando a restauração em 10 segundos..."
        sleep 10
        
        # Define VM mas não inicia (retorna código 2)
        return 2
    fi

    echo "🎯 Interfaces livres para mapeamento:"
    printf '   • %s\n' "${available_for_mapping[@]}"
    echo ""
    echo "--- Mapeamento realizado ---"

    # MAPEAR CADA INTERFACE
    mapping_index=0
    for xml_int in "${xml_interfaces[@]}"; do
        # Se existe, manter
        if printf '%s\n' "${existing_interfaces[@]}" | grep -q "^$xml_int$"; then
            echo "  ✓ $xml_int → $xml_int (mantida)"
            continue
        fi

        # Não existe - mapear
        if [ $mapping_index -lt ${#available_for_mapping[@]} ]; then
            new_interface="${available_for_mapping[$mapping_index]}"
            echo "  🔄 $xml_int → $new_interface (remapeada)"
            
            # Substituir no XML
            sed -i "0,/dev='$xml_int'/s//dev='$new_interface'/" "$xml_file"
            
            ((mapping_index++))
        else
            echo "  ❌ $xml_int → FALHA (sem interfaces livres)"
        fi
    done

    echo "----------------------------"
    echo ""
    echo "✅ XML modificado com sucesso!"
    echo "📄 Usando: $xml_file"
    
    return 0
}

function etapa03 {
  if ! [ -f /srv/restored3.lock ]; then
      echo "=== ETAPA 3: Restaurando VMs pfSense ==="
      
      find "$pathrestore" -type f -iname "*pfsense*" | while IFS= read -r disk_file; do
        file_type=$(file -b "$disk_file")

        # Ignora arquivos XML ou texto
        if echo "$file_type" | grep -Eqi "XML|ASCII text|UTF-8 text"; then
          echo "Ignorado (não é disco): $(basename "$disk_file") → Tipo: $file_type"
          continue
        fi

        # Aceita arquivos que parecem ser discos
        if echo "$file_type" | grep -Eqi "qemu|qcow|virtual|boot sector|disk image|DOS/MBR|data"; then
          echo "Restaurando disco: $(basename "$disk_file")"
          sudo rsync -aHAXv --numeric-ids --sparse "$disk_file" /var/lib/libvirt/images/
        else
         echo "Ignorado (tipo desconhecido): $(basename "$disk_file") → Tipo: $file_type"
        fi
      done
      
      # Procurar XML no backup
      xml_file_backup=$(find "$pathrestore" -iname "pf*.xml" | head -1)
      
      if [ -n "$xml_file_backup" ]; then
          echo "📄 XML no backup: $(basename "$xml_file_backup")"
          
          # Copiar para área de trabalho
          xml_file_work="/tmp/pfsense-restore.xml"
          cp "$xml_file_backup" "$xml_file_work"
          echo "✓ Copiado para: $xml_file_work"
          echo ""
          
          # Detectar interface Docker
          docker_interface=$(docker network inspect macvlan 2>/dev/null | jq -r '.[0].Options.parent' 2>/dev/null)
          original_parent="$docker_interface"
          
          if [ -z "$original_parent" ] || [ "$original_parent" = "null" ]; then
            echo "❌ Rede macvlan não encontrada - execute etapa01 primeiro"
            return 1
          fi
          
          # MAPEAR INTERFACES
          map_xml_interfaces "$xml_file_work" "$original_parent"
          mapping_result=$?
          
          echo ""
          
          # Definir VM
          if virsh define "$xml_file_work"; then
              vm_name=$(grep -oP '<name>\K[^<]+' "$xml_file_work")
              echo "✅ VM definida: $vm_name"
              
              # Iniciar apenas se mapeamento foi bem-sucedido
              if [ $mapping_result -eq 2 ]; then
                  echo ""
                  echo "⏭  VM NÃO iniciada (interfaces insuficientes ou bloqueadas)"
                  echo "📝 XML salvo em: /tmp/pfsense-restore.xml"
                  echo "📝 Configuração manual necessária após conclusão do restore"
                  echo ""
              else
                  if virsh autostart "$vm_name" 2>/dev/null; then
                    echo "✅ Autostart configurado - VM iniciará com o host"
                  fi
                  echo ""
                  echo "🚀 Iniciando VM..."
                  if virsh start "$vm_name" 2>/dev/null; then
                      echo "✅ VM iniciada com sucesso!"
                  else
                      echo "⚠️  Tentando iniciar com --force-boot..."
                      virsh start "$vm_name" --force-boot 2>&1 | tee /tmp/vm_start_error.log
                      if [ "${PIPESTATUS[0]}" -eq 0 ]; then
                          echo "✅ VM iniciada (forçada)"
                      else
                          echo "❌ Falha ao iniciar VM"
                          echo "📝 Log salvo em: /tmp/vm_start_error.log"
                          echo "🔧 Desativando autostart devido à falha..."
                          if virsh autostart --disable "$vm_name" 2>/dev/null; then
                              echo "✅ Autostart desativado - VM não iniciará automaticamente"
                          else
                              echo "⚠️  Não foi possível desativar autostart"
                          fi
                      fi
                  fi
              fi
              
              # Salvar XML final
              sudo cp "$xml_file_work" "/var/lib/libvirt/qemu/$vm_name.xml"
              echo "✓ XML definitivo salvo em: /var/lib/libvirt/qemu/$vm_name.xml"
              
          else
              echo "❌ Falha ao definir VM"
          fi
      fi
      
      sudo touch /srv/restored3.lock
      echo "✅ ETAPA 3 concluída"
  else
      echo "⏭ ETAPA 3 já executada"
  fi
}

function etapa031 {
  if ! [ -f /srv/restored031-wait.lock ]; then
      echo "=== ETAPA 031: Aguardando pfSense ficar online ==="
      
      # Verificar se VM pfSense existe
      vm_name=$(virsh list --all | grep -i pfsense | awk '{print $2}')
      
      if [ -z "$vm_name" ]; then
          echo "⚠️  Nenhuma VM pfSense encontrada - pulando verificação"
          sudo touch /srv/restored031-wait.lock
          return 0
      fi
      
      # Verificar se VM está rodando
      vm_state=$(virsh list --state-running | grep -i "$vm_name")
      if [ -z "$vm_state" ]; then
          echo "⚠️  VM pfSense não está rodando - pulando verificação"
          sudo touch /srv/restored031-wait.lock
          return 0
      fi
      
      echo "🔍 VM pfSense detectada: $vm_name"
      echo "📡 Tentando detectar IP do pfSense..."
      
      # Tentar obter IP do pfSense do YAML
      pfsense_ip=$(yq -r '.Rede.gateway' /srv/system.yaml 2>/dev/null)
      
      if [ -z "$pfsense_ip" ] || [ "$pfsense_ip" = "null" ]; then
          echo "⚠️  IP do pfSense não encontrado no system.yaml"
          echo "💡 Tentando detectar via ARP/network scan..."
          
          # Tentar detectar via subnet
          subnet=$(yq -r '.Rede.subnet' /srv/system.yaml 2>/dev/null)
          if [ -n "$subnet" ] && [ "$subnet" != "null" ]; then
              # Extrair primeiro IP do range (geralmente o gateway)
              pfsense_ip=$(echo "$subnet" | sed 's|/.*||' | awk -F. '{print $1"."$2"."$3".1"}')
              echo "🎯 IP estimado: $pfsense_ip"
          else
              echo "❌ Não foi possível determinar IP do pfSense"
              echo "⏭️  Continuando sem verificação (pode causar problemas nos containers)"
              sudo touch /srv/restored031-wait.lock
              return 0
          fi
      fi
      
      echo "🎯 IP do pfSense: $pfsense_ip"
      echo ""
      echo "⏳ Aguardando pfSense responder (timeout: 3 minutos)..."
      echo "   Isso é normal - VM precisa bootar e pfSense precisa carregar para continuarmos."
      if [ "$rede00" = "1" ]; then
        echo "   Rede Customizada: Se demorar demais para pingar, ou este menu fechar sem concluir ou reiniciar,"
        echo "tecle CTRL+ALT+F2, faça login, digite startx e pelo Virt-Manager confira se o pfSense está solicitando ajuste manual das placas de rede!"
      fi
      echo ""
      
      # Configurações de timeout
      MAX_WAIT=180  # 3 minutos
      INTERVAL=5    # 5 segundos entre tentativas
      elapsed=0
      
      # Barra de progresso
      while [ $elapsed -lt $MAX_WAIT ]; do
          # Tentar ping
          if ping -c 1 -W 2 "$pfsense_ip" &>/dev/null; then
              echo ""
              echo "✅ pfSense respondeu ao ping!"
              echo "⏱️  Tempo decorrido: ${elapsed}s"
              
              # Esperar mais 10s para garantir que serviços estejam prontos
              echo "⏳ Aguardando mais 10s para estabilização dos serviços..."
              sleep 10
              
              echo "✅ pfSense está pronto!"
              sudo touch /srv/restored031-wait.lock
              return 0
          fi
          
          # Atualizar progresso
          printf "\r⏳ Aguardando... %ds/%ds " "$elapsed" "$MAX_WAIT"
          
          sleep $INTERVAL
          elapsed=$((elapsed + INTERVAL))
          
          # Verificar se VM ainda está rodando a cada 30s
          if [ $((elapsed % 30)) -eq 0 ]; then
              if ! virsh list --state-running | grep -q "$vm_name"; then
                  echo ""
                  echo "❌ VM pfSense parou de responder durante a espera!"
                  echo "🔧 Tentando reiniciar VM..."
                  
                  if virsh start "$vm_name" 2>/dev/null; then
                      echo "✅ VM reiniciada - resetando timer"
                      elapsed=0
                  else
                      echo "❌ Falha ao reiniciar VM"
                      break
                  fi
              fi
          fi
      done
      
      # Timeout atingido
      echo ""
      echo "⚠️  TIMEOUT: pfSense não respondeu após 3 minutos"
      echo ""
      echo "POSSÍVEIS CAUSAS:"
      echo "  • IP do pfSense está incorreto"
      echo "  • VM está com problema de boot"
      echo "  • Interfaces de rede mal configuradas"
      echo "  • Firewall bloqueando ICMP"
      echo ""
      echo "DIAGNÓSTICO:"
      echo "Tecle CTRL+ALT+F2, faça login, digite startx e pelo Virt-Manager confira se o pfSense está solicitando ajuste manual das placas de rede!"
      echo ""
      
      read -r -p "Deseja continuar mesmo assim? (S/n): " resposta
      resposta=$(echo "$resposta" | tr '[:upper:]' '[:lower:]')
      
      if [[ "$resposta" =~ ^(s|sim|y|yes|)$ ]]; then
          echo "⚠️  Continuando restore (containers podem falhar)"
          sudo touch /srv/restored031-wait.lock
          return 0
      else
          echo "❌ Restore cancelado pelo usuário"
          exit 1
      fi
      
  else
      echo "⏭️  ETAPA 031 já executada (lock existe)"
  fi
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
etapa031

sudo reboot

exit 0
