#!/bin/bash

yamlbase="/srv/system.yaml"
yamlextra="/srv/containers.yaml"

export yamlbase
export yamlextra

LOG_FILE="/var/log/restore-total-2-$(date +%Y%m%d_%H%M%S).log"
exec 1> >(sudo tee -a "$LOG_FILE")
exec 2>&1

echo "=== Restore iniciado em $(date) ==="
echo "Log salvo em: $LOG_FILE"

function etapa00-restored {
  if [ -f /srv/restored.lock ]; then
    clear
    echo ""
    echo "ERRO 01: ⏭ ESTE SERVIDOR JÁ FOI RESTAURADO COMPLETAMENTE ANTERIORMENTE! (lock existe)"
    echo "Se o sistema apresenta falhas nos serviços, recomendo que formate e refaça o sistema restaurando novamente."
    echo "Operacao cancelada. Saindo em 5 segundos..."
    sleep 5
    exit 1
  fi
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

function etapa00-continue {
  if mountpoint -q /mnt/bkpsys; then
    echo "✓ Backup já está montado"
    pathrestore=$(find /mnt/bkpsys -name "*.tar.lz4" 2>/dev/null | head -1 | xargs dirname)
  else
    echo "Montando backup..."
    if sudo mount -t ext4 LABEL=bkpsys /mnt/bkpsys; then
      echo "✓ Backup montado com sucesso"
      echo "✓ ETAPA 0 concluída"
      pathrestore=$(find /mnt/bkpsys -name "*.tar.lz4" 2>/dev/null | head -1 | xargs dirname)
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

function etapa05-restore-bkpcont {
  if ! [ -f /srv/restored5.lock ]; then
      echo "=== ETAPA 5: Restaurando containers (mais recente de cada) ==="

      # Criar diretório se não existir
      sudo mkdir -p /srv/containers
      sudo mkdir -p /srv/scripts

      # Restaurar scripts
      if [ -d "$pathrestore/scripts" ]; then
        echo "📁 Restaurando /srv/scripts..."
        sudo rsync -aHAXv --numeric-ids --delete "$pathrestore/scripts/" /srv/scripts/
        echo "✅ Scripts restaurados"
      else
        echo "⚠️  Diretório scripts não encontrado no backup"
      fi
      
      # Restaurar YAMLs
      if [ -f "$pathrestore/system.yaml" ]; then
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
          #basename_clean=$(echo "$filename" | sed 's/-[0-9][0-9]_[0-9][0-9]_[0-9][0-9]\.tar\.lz4$//')
          basename_clean="${filename%-[0-9][0-9]_[0-9][0-9]_[0-9][0-9].tar.lz4}"

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

      sudo touch /srv/restored5.lock; echo "✓ ETAPA 5 concluída"
  else
      echo "⏭ ETAPA 5 já executada (lock existe)"
  fi
}

function etapa06-start-containers {
  if ! [ -f /srv/restored6.lock ]; then
      echo "=== ETAPA 6: Restaurando containers via orchestration ==="

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
              ["kasm"]="14-kasm"
              ["kuma"]="15-kuma"
              ["lan-speed-test"]="16-openspeedtest"
              ["chromium-browser"]="17-Chromium"
              ["chrome-browser"]="18-google-chrome"
              ["jellyfin"]="19-jellyfin"
              ["wan-speed-test"]="20-myspeed-tracker"
              ["qbittorrent"]="21-qbittorrent"
              ["aptcache"]="22-apt-cacher"
              ["meshstatic"]="23-meshstatic-web"
              ["plocate"]="24-plocate"
              ["ferdium"]="25-ferdium"
              ["nextcloud"]="26-nextcloud"
              ["openfire"]="27-openfire"
              ["filebrowser"]="28-filebrowser"
              ["mariadb"]="29-mariadb"
              ["ntfy"]="30-ntfy_server"
              ["minecraft"]="31-minecraft-server"
              ["docker-macos"]="32-macOS-in-Docker"
              ["reverse-proxy"]="33-reverseproxy"
              ["onlyoffice"]="34-onlyoffice"
              ["docker-windows"]="35-Windows-in-Docker"
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

          # Obter todas as img_base únicas do YAML e popular array
          mapfile -t unique_images < <(yq -r '[.[] | .img_base] | unique | .[]' /srv/containers.yaml)

          echo "Imagens base encontradas:"
          for img in "${unique_images[@]}"; do
              count=$(yq -r "[.[] | select(.img_base == \"$img\")] | length" /srv/containers.yaml)
              echo "  • $img ($count container(s))"
          done
          echo ""

          # Arrays para tracking de sucessos e falhas
          declare -a successful_images
          declare -a failed_images
          
          # Para cada img_base única, processar via orchestration
          rm -f /srv/lockfile
          
          for img_base in "${unique_images[@]}"; do
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

                  # Sistema de retry: máximo 3 tentativas
                  MAX_RETRIES=3
                  attempt=1
                  success=false

                  while [ $attempt -le $MAX_RETRIES ]; do
                      echo ""
                      echo "🔄 Tentativa $attempt de $MAX_RETRIES para $img_base..."
                      
                      # Executar orchestration
                      bash /tmp/orchestration
                      
                      # Aguardar containers iniciarem
                      sleep 5
                      
                      # Verificar status de TODOS os containers desta img_base
                      all_running=true
                      
                      echo "Verificando status dos containers:"
                      while IFS= read -r container_name; do
                          if [ -n "$container_name" ]; then
                              status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null)
                              
                              if [ "$status" = "running" ]; then
                                  echo "  ✅ $container_name: running"
                              else
                                  echo "  ❌ $container_name: $status (esperado: running)"
                                  all_running=false
                              fi
                          fi
                      done <<< "$containers"
                      
                      # Se todos estão running, sucesso!
                      if [ "$all_running" = true ]; then
                          echo "✅ Todos os containers de $img_base estão rodando!"
                          success=true
                          successful_images+=("$img_base")
                          break
                      else
                          echo "⚠️  Nem todos os containers subiram corretamente"
                          
                          if [ $attempt -lt $MAX_RETRIES ]; then
                              echo "🔄 Tentando novamente em 10 segundos..."
                              sleep 10
                              
                              # Limpar containers com problema antes de retry
                              echo "🧹 Removendo containers com falha para retry..."
                              while IFS= read -r container_name; do
                                  if [ -n "$container_name" ]; then
                                      docker rm -f "$container_name" 2>/dev/null && echo "  • $container_name removido"
                                  fi
                              done <<< "$containers"
                          fi
                      fi
                      
                      ((attempt++))
                  done
                  
                  rm -f /srv/lockfile
                  
                  # Se após 3 tentativas não funcionou
                  if [ "$success" = false ]; then
                      echo ""
                      echo "❌ FALHA DEFINITIVA: $img_base não subiu após $MAX_RETRIES tentativas"
                      echo "📝 Containers afetados:"
                      echo "$containers" | while read -r cont; do
                          echo "  • $cont"
                      done
                      echo "⏭️  Pulando para próximo img_base..."
                      echo ""
                      failed_images+=("$img_base")
                      
                      # Log detalhado no arquivo principal
                      {
                          echo ""
                          echo "========================================="
                          echo "ERRO: img_base $img_base FALHOU"
                          echo "Data: $(date)"
                          echo "Tentativas: $MAX_RETRIES"
                          echo "Containers afetados:"
                          echo "$containers"
                          echo "========================================="
                          echo ""
                      } | sudo tee -a "$LOG_FILE" > /dev/null
                  fi

                  echo "----------------------------------------"
                  sleep 3  # Pausa entre diferentes tipos de container

              else
                  echo "⚠️  Nenhum script mapeado para img_base: $img_base"
                  containers=$(yq -r "to_entries[] | select(.value.img_base == \"$img_base\") | .key" /srv/containers.yaml)
                  echo "Containers afetados:"
                  echo "$containers" | while read -r cont; do
                      echo "  • $cont"
                  done
                  echo ""
                  failed_images+=("$img_base (sem script mapeado)")
              fi
          done

          # Limpar lockfile final
          rm -f /srv/lockfile

          echo ""
          echo "========================================="
          echo "=== RESUMO DA RESTAURAÇÃO DE CONTAINERS ==="
          echo "========================================="
          
          total_containers=$(yq -r 'keys | length' /srv/containers.yaml)
          total_images=${#unique_images[@]}
          
          echo "Total de img_base processadas: $total_images"
          echo "Total de containers no YAML: $total_containers"
          echo ""
          
          if [ ${#successful_images[@]} -gt 0 ]; then
              echo "✅ IMG_BASE COM SUCESSO (${#successful_images[@]}):"
              printf '  ✓ %s\n' "${successful_images[@]}"
              echo ""
          fi
          
          if [ ${#failed_images[@]} -gt 0 ]; then
              echo "❌ IMG_BASE COM FALHA (${#failed_images[@]}):"
              printf '  ✗ %s\n' "${failed_images[@]}"
              echo ""
              echo "⚠️  ATENÇÃO: Alguns containers NÃO foram restaurados!"
              echo "   Verifique o log em: $LOG_FILE"
              echo "   Será necessária intervenção manual após o restore."
              echo ""
          else
              echo "🎉 Todos os containers foram restaurados com sucesso!"
              echo ""
          fi
          
          echo "✓ Restauração automática concluída"
          echo "========================================="

      else
          echo "⚠️  Arquivo containers.yaml não encontrado, pulando restauração de containers"
      fi

      sudo touch /srv/restored6.lock; echo "✓ ETAPA 6 concluída"
  else
      echo "⏭️  ETAPA 6 já executada (lock existe)"
  fi
}

function etapa07-cron {
  if ! [ -f /srv/restored7.lock ]; then
    sudo crontab "$pathrestore"/crontab-bkp
    sudo touch /srv/restored7.lock; echo "✓ ETAPA 7 concluída"
  else
    echo "⏭ ETAPA 7 já executada (lock existe)"
  fi
}

function etapa08-end {
  datetime0=$(date +"%d/%m/%Y - %H:%M")
  sudo yq -i ".Informacoes.Data_Ultima_Reinstalacao = \"${datetime0}\"" "$yamlbase"
  sudo rm /srv/restored*
  echo "=== RESTORE COMPLETO ==="
  sleep 3
  echo "Reiniciando..."
  sudo touch /srv/restored.lock
}

if [ -f /srv/restored4.lock ]; then
  etapa00-restored
  etapa00-github
  etapa00-continue

  etapa05-restore-bkpcont
  etapa06-start-containers
  etapa07-cron
  etapa08-end

  sudo reboot
else
  clear
  echo "Nao identifiquei uma restauracao previamente iniciada."; sleep 2
  echo "Nao pule etapas!"; sleep 1
  echo "Volte ao menu anterior e execute a partir de 'Refazer A: Base e Firewall'"; sleep 3
  echo "Saindo..."; sleep 1
  exit 1
fi  

exit 0
