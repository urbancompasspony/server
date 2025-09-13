#!/bin/bash

# ================================================================================================
# LiniteBackup - Sistema Unificado de Backup
# Versão: 1.0
# ================================================================================================

export LANG=C
export LC_ALL=C

# Configurações
BACKUP_BASE="/srv/backup"
BACKUP_DATE=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="$BACKUP_BASE/backup_$BACKUP_DATE"
YAML_SYSTEM="/srv/system.yaml"
YAML_CONTAINERS="/srv/containers.yaml"
RESTORE_SCRIPT="/srv/scripts/restore-full.sh"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ================================================================================================
# FUNÇÕES AUXILIARES
# ================================================================================================

function print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

function print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

function print_info() {
    echo -e "${YELLOW}[i]${NC} $1"
}

function check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Este script deve ser executado como root!"
        exit 1
    fi
}

function check_dependencies() {
    local deps=("yq" "docker" "rsync" "tar")
    for dep in "${deps[@]}"; do
        if ! command -v $dep &> /dev/null; then
            print_error "Dependência não encontrada: $dep"
            exit 1
        fi
    done
    print_status "Todas as dependências encontradas"
}

# ================================================================================================
# COLETA DE INFORMAÇÕES DO SISTEMA
# ================================================================================================

function collect_system_info() {
    print_info "Coletando informações do sistema..."
    
    local manifest="$BACKUP_DIR/manifest.yaml"
    
    # Informações básicas
    yq -i ".backup_info.date = \"$BACKUP_DATE\"" "$manifest"
    yq -i ".backup_info.hostname = \"$(hostname)\"" "$manifest"
    yq -i ".backup_info.kernel = \"$(uname -r)\"" "$manifest"
    yq -i ".backup_info.os = \"$(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2)\"" "$manifest"
    
    # Informações de rede
    local primary_ip=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')
    yq -i ".network.primary_ip = \"$primary_ip\"" "$manifest"
    
    # Interfaces de rede
    for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -v lo); do
        local mac=$(ip link show $iface | grep ether | awk '{print $2}')
        local ip=$(ip -4 addr show $iface | grep inet | awk '{print $2}' | head -1)
        if [[ ! -z "$mac" ]]; then
            yq -i ".network.interfaces.$iface.mac = \"$mac\"" "$manifest"
            yq -i ".network.interfaces.$iface.ip = \"$ip\"" "$manifest"
        fi
    done
    
    # Discos e partições
    while IFS= read -r line; do
        disk=$(echo $line | awk '{print $1}')
        mount=$(echo $line | awk '{print $6}')
        size=$(echo $line | awk '{print $2}')
        used=$(echo $line | awk '{print $3}')
        
        yq -i ".storage.\"$mount\".device = \"$disk\"" "$manifest"
        yq -i ".storage.\"$mount\".size = \"$size\"" "$manifest"
        yq -i ".storage.\"$mount\".used = \"$used\"" "$manifest"
    done < <(df -h | grep '^/dev')
    
    print_status "Informações do sistema coletadas"
}

# ================================================================================================
# BACKUP DE CONFIGURAÇÕES DO SISTEMA
# ================================================================================================

function backup_system_configs() {
    print_info "Fazendo backup das configurações do sistema..."
    
    local sys_backup="$BACKUP_DIR/system"
    mkdir -p "$sys_backup"
    
    # Lista de arquivos/diretórios importantes
    local configs=(
        "/etc/netplan"
        "/etc/network"
        "/etc/NetworkManager/system-connections"
        "/etc/hostname"
        "/etc/hosts"
        "/etc/fstab"
        "/etc/crypttab"
        "/etc/systemd/network"
        "/etc/sysctl.d"
        "/etc/modules-load.d"
        "/etc/modprobe.d"
        "/etc/apt/sources.list"
        "/etc/apt/sources.list.d"
        "/etc/crontab"
        "/var/spool/cron/crontabs"
        "/etc/ssh/sshd_config"
        "/etc/sudoers"
        "/etc/sudoers.d"
        "/etc/group"
        "/etc/passwd"
        "/etc/shadow"
        "/etc/gshadow"
        "/home/*/.ssh"
        "/root/.ssh"
        "/etc/update-motd.d"
        "/etc/systemd/journald.conf"
    )
    
    for config in "${configs[@]}"; do
        if [[ -e "$config" ]]; then
            # Cria estrutura de diretórios
            local dest_dir="$sys_backup/$(dirname $config)"
            mkdir -p "$dest_dir"
            
            # Copia preservando permissões
            cp -a "$config" "$dest_dir/" 2>/dev/null && \
                print_status "Backup: $config" || \
                print_error "Falha ao copiar: $config"
        fi
    done
    
    # Backup de pacotes instalados
    print_info "Salvando lista de pacotes instalados..."
    dpkg --get-selections > "$sys_backup/packages.list"
    apt-mark showauto > "$sys_backup/packages-auto.list"
    apt-mark showmanual > "$sys_backup/packages-manual.list"
    
    # Backup de serviços habilitados
    systemctl list-unit-files --state=enabled > "$sys_backup/services-enabled.list"
    
    print_status "Configurações do sistema salvas"
}

# ================================================================================================
# BACKUP DOS CONTAINERS DOCKER
# ================================================================================================

function backup_docker_containers() {
    print_info "Fazendo backup dos containers Docker..."
    
    local docker_backup="$BACKUP_DIR/containers"
    mkdir -p "$docker_backup"
    
    # Salva informações da rede macvlan se existir
    if docker network inspect macvlan &>/dev/null; then
        docker network inspect macvlan > "$docker_backup/macvlan-network.json"
        print_status "Configuração da rede macvlan salva"
    fi
    
    # Para cada container no YAML
    if [[ -f "$YAML_CONTAINERS" ]]; then
        # Lista todos os containers
        local containers=$(yq -r 'keys | .[]' "$YAML_CONTAINERS")
        
        for container in $containers; do
            print_info "Processando container: $container"
            
            # Verifica se o container existe
            if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
                # Para o container para consistência
                docker stop "$container" &>/dev/null
                
                # Exporta a imagem do container
                print_info "Exportando container $container..."
                docker export "$container" | gzip > "$docker_backup/${container}.tar.gz"
                
                # Backup dos volumes
                if [[ -d "/srv/containers/$container" ]]; then
                    print_info "Backup dos volumes de $container..."
                    tar -czf "$docker_backup/${container}_volumes.tar.gz" \
                        -C /srv/containers "$container" 2>/dev/null
                fi
                
                # Salva o comando de criação
                docker inspect "$container" > "$docker_backup/${container}_inspect.json"
                
                # Reinicia o container
                docker start "$container" &>/dev/null
                
                print_status "Container $container processado"
            else
                print_error "Container $container não encontrado"
            fi
        done
    fi
    
    # Backup das imagens Docker customizadas
    print_info "Salvando lista de imagens Docker..."
    docker images --format "{{.Repository}}:{{.Tag}}" > "$docker_backup/docker-images.list"
    
    print_status "Backup dos containers concluído"
}

# ================================================================================================
# BACKUP DOS ARQUIVOS YAML
# ================================================================================================

function backup_yaml_configs() {
    print_info "Fazendo backup dos arquivos YAML..."
    
    local yaml_backup="$BACKUP_DIR/configs"
    mkdir -p "$yaml_backup"
    
    # Copia os YAMLs principais
    [[ -f "$YAML_SYSTEM" ]] && cp "$YAML_SYSTEM" "$yaml_backup/"
    [[ -f "$YAML_CONTAINERS" ]] && cp "$YAML_CONTAINERS" "$yaml_backup/"
    
    # Copia scripts importantes
    if [[ -d "/srv/scripts" ]]; then
        cp -r /srv/scripts "$yaml_backup/"
    fi
    
    print_status "Arquivos YAML salvos"
}

# ================================================================================================
# BACKUP DE DADOS CUSTOMIZADOS
# ================================================================================================

function backup_custom_data() {
    print_info "Fazendo backup de dados customizados..."
    
    local custom_backup="$BACKUP_DIR/custom"
    mkdir -p "$custom_backup"
    
    # Lista de diretórios customizados para backup
    local custom_dirs=(
        "/mnt/disk01"
        "/mnt/disk02"
        "/srv/data"
        "/opt"
    )
    
    for dir in "${custom_dirs[@]}"; do
        if [[ -d "$dir" ]] && [[ $(ls -A "$dir") ]]; then
            print_info "Backup de $dir..."
            local dir_name=$(basename "$dir")
            tar -czf "$custom_backup/${dir_name}.tar.gz" -C "$(dirname $dir)" "$dir_name" 2>/dev/null
        fi
    done
    
    print_status "Dados customizados salvos"
}

# ================================================================================================
# CRIAR SCRIPT DE RESTAURAÇÃO
# ================================================================================================

function create_restore_script() {
    print_info "Criando script de restauração..."
    
    cat > "$BACKUP_DIR/restore.sh" << 'EOF'
#!/bin/bash

# Script de Restauração LiniteBackup
# Gerado automaticamente

BACKUP_DIR="$(dirname "$0")"
MANIFEST="$BACKUP_DIR/manifest.yaml"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

function print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
function print_error() { echo -e "${RED}[✗]${NC} $1"; }
function print_info() { echo -e "${YELLOW}[i]${NC} $1"; }

# Verifica root
[[ $EUID -ne 0 ]] && { print_error "Execute como root!"; exit 1; }

echo "================================"
echo "LiniteBackup - Restauração"
echo "================================"
echo ""

# Mostra informações do backup
echo "Informações do Backup:"
yq '.backup_info' "$MANIFEST"
echo ""

read -p "Deseja continuar com a restauração? (s/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    exit 0
fi

# 1. Restaura configurações do sistema
print_info "Restaurando configurações do sistema..."
if [[ -d "$BACKUP_DIR/system" ]]; then
    # Restaura netplan
    [[ -d "$BACKUP_DIR/system/etc/netplan" ]] && \
        cp -a "$BACKUP_DIR/system/etc/netplan"/* /etc/netplan/
    
    # Restaura hosts e hostname
    [[ -f "$BACKUP_DIR/system/etc/hostname" ]] && \
        cp "$BACKUP_DIR/system/etc/hostname" /etc/
    [[ -f "$BACKUP_DIR/system/etc/hosts" ]] && \
        cp "$BACKUP_DIR/system/etc/hosts" /etc/
    
    # Restaura fstab (com cuidado)
    if [[ -f "$BACKUP_DIR/system/etc/fstab" ]]; then
        cp /etc/fstab /etc/fstab.bak
        cp "$BACKUP_DIR/system/etc/fstab" /etc/fstab.restore
        print_info "fstab salvo em /etc/fstab.restore - revise antes de aplicar"
    fi
    
    # Restaura configurações SSH
    [[ -d "$BACKUP_DIR/system/etc/ssh" ]] && \
        cp -a "$BACKUP_DIR/system/etc/ssh"/* /etc/ssh/
    
    # Restaura crontabs
    if [[ -d "$BACKUP_DIR/system/var/spool/cron/crontabs" ]]; then
        cp -a "$BACKUP_DIR/system/var/spool/cron/crontabs"/* /var/spool/cron/crontabs/
        chmod 600 /var/spool/cron/crontabs/*
    fi
    
    print_status "Configurações do sistema restauradas"
fi

# 2. Restaura YAMLs e scripts
print_info "Restaurando arquivos YAML e scripts..."
if [[ -d "$BACKUP_DIR/configs" ]]; then
    [[ -f "$BACKUP_DIR/configs/system.yaml" ]] && \
        cp "$BACKUP_DIR/configs/system.yaml" /srv/
    [[ -f "$BACKUP_DIR/configs/containers.yaml" ]] && \
        cp "$BACKUP_DIR/configs/containers.yaml" /srv/
    [[ -d "$BACKUP_DIR/configs/scripts" ]] && \
        cp -r "$BACKUP_DIR/configs/scripts" /srv/
fi

# 3. Restaura containers Docker
print_info "Restaurando containers Docker..."
if [[ -d "$BACKUP_DIR/containers" ]]; then
    # Recria rede macvlan se necessário
    if [[ -f "$BACKUP_DIR/containers/macvlan-network.json" ]]; then
        if ! docker network ls | grep -q macvlan; then
            # Extrai configurações da rede
            SUBNET=$(jq -r '.[0].IPAM.Config[0].Subnet' "$BACKUP_DIR/containers/macvlan-network.json")
            GATEWAY=$(jq -r '.[0].IPAM.Config[0].Gateway' "$BACKUP_DIR/containers/macvlan-network.json")
            PARENT=$(jq -r '.[0].Options["parent"]' "$BACKUP_DIR/containers/macvlan-network.json")
            
            docker network create -d macvlan \
                --subnet="$SUBNET" \
                --gateway="$GATEWAY" \
                -o parent="$PARENT" \
                macvlan
            
            print_status "Rede macvlan recriada"
        fi
    fi
    
    # Restaura volumes dos containers
    for volume_file in "$BACKUP_DIR/containers"/*_volumes.tar.gz; do
        if [[ -f "$volume_file" ]]; then
            container_name=$(basename "$volume_file" _volumes.tar.gz)
            print_info "Restaurando volumes de $container_name..."
            tar -xzf "$volume_file" -C /srv/containers/
        fi
    done
    
    # Importa containers
    for container_file in "$BACKUP_DIR/containers"/*.tar.gz; do
        if [[ -f "$container_file" ]] && [[ ! "$container_file" == *"_volumes.tar.gz" ]]; then
            container_name=$(basename "$container_file" .tar.gz)
            print_info "Importando container $container_name..."
            
            # Para containers existentes
            docker stop "$container_name" 2>/dev/null
            docker rm "$container_name" 2>/dev/null
            
            # Importa a imagem
            docker import "$container_file" "restored:$container_name"
            
            print_info "Container $container_name importado - use o script original para recriá-lo"
        fi
    done
    
    print_status "Containers Docker processados"
fi

# 4. Reinstala pacotes
if [[ -f "$BACKUP_DIR/system/packages.list" ]]; then
    read -p "Deseja reinstalar os pacotes? (s/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        print_info "Reinstalando pacotes..."
        apt update
        dpkg --set-selections < "$BACKUP_DIR/system/packages.list"
        apt-get dselect-upgrade -y
    fi
fi

print_status "Restauração concluída!"
print_info "Revise as configurações e reinicie o sistema se necessário"
EOF
    
    chmod +x "$BACKUP_DIR/restore.sh"
    print_status "Script de restauração criado"
}

# ================================================================================================
# COMPRESSÃO FINAL
# ================================================================================================

function compress_backup() {
    print_info "Comprimindo backup..."
    
    cd "$BACKUP_BASE"
    tar -czf "linite_backup_${BACKUP_DATE}.tar.gz" "backup_$BACKUP_DATE"
    
    # Calcula hash para integridade
    sha256sum "linite_backup_${BACKUP_DATE}.tar.gz" > "linite_backup_${BACKUP_DATE}.sha256"
    
    # Remove diretório temporário se compressão foi bem sucedida
    if [[ $? -eq 0 ]]; then
        rm -rf "backup_$BACKUP_DATE"
        print_status "Backup comprimido: linite_backup_${BACKUP_DATE}.tar.gz"
    else
        print_error "Erro na compressão - mantendo diretório original"
    fi
}

# ================================================================================================
# UPLOAD PARA NUVEM (OPCIONAL)
# ================================================================================================

function upload_to_cloud() {
    # Verifica se rclone está configurado
    if command -v rclone &> /dev/null && rclone listremotes | grep -q .; then
        read -p "Deseja fazer upload do backup para a nuvem? (s/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            print_info "Fazendo upload para a nuvem..."
            
            # Lista remotes disponíveis
            echo "Remotes disponíveis:"
            rclone listremotes
            
            read -p "Digite o nome do remote: " remote
            
            if rclone copy "$BACKUP_BASE/linite_backup_${BACKUP_DATE}.tar.gz" \
                "${remote}:LiniteBackups/" --progress; then
                print_status "Upload concluído"
            else
                print_error "Erro no upload"
            fi
        fi
    fi
}

# ================================================================================================
# FUNÇÃO PRINCIPAL
# ================================================================================================

function main() {
    clear
    echo "╔══════════════════════════════════════╗"
    echo "║     LiniteBackup - Backup Total      ║"
    echo "║           Versão 1.0                 ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    
    check_root
    check_dependencies
    
    # Cria estrutura de diretórios
    mkdir -p "$BACKUP_DIR"
    
    # Executa as etapas do backup
    collect_system_info
    backup_yaml_configs
    backup_system_configs
    backup_docker_containers
    backup_custom_data
    create_restore_script
    compress_backup
    upload_to_cloud
    
    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║        Backup Concluído!             ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    echo "Arquivo: $BACKUP_BASE/linite_backup_${BACKUP_DATE}.tar.gz"
    echo "Hash: $BACKUP_BASE/linite_backup_${BACKUP_DATE}.sha256"
    echo ""
    
    # Mostra tamanho do backup
    du -h "$BACKUP_BASE/linite_backup_${BACKUP_DATE}.tar.gz"
}

# Executa
main "$@"
