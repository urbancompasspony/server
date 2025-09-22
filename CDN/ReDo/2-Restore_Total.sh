# ETAPA 5: Restaurar containers automaticamente (VERSÃO CORRIGIDA)
##########################################################################################################################
if ! [ -f /srv/restored4.lock ]; then
    echo "=== ETAPA 5: Restaurando containers automaticamente ==="
    
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
    echo "✓ ETAPA 5 concluída"
fi
