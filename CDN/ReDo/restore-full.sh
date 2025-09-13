#!/bin/bash

# ================================================================================================
# LiniteBackup - Restauração Rápida
# Versão: 1.0
# ================================================================================================

export LANG=C
export LC_ALL=C

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

function print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
function print_error() { echo -e "${RED}[✗]${NC} $1"; }
function print_info() { echo -e "${YELLOW}[i]${NC} $1"; }
function print_header() { echo -e "${BLUE}==>${NC} $1"; }

# ================================================================================================
# RESTAURAÇÃO EM SERVIDOR NOVO
# ================================================================================================

function prepare_new_server() {
    clear
    echo "╔══════════════════════════════════════╗"
    echo "║   LiniteBackup - Restauração Total   ║"
    echo "║         Servidor Novo                ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    
    # 1. Instala o sistema base Linite
    print_header "Etapa 1: Instalando sistema base Linite"
    if [[ ! -f /srv/system.yaml ]]; then
        print_info "Baixando e executando instalador Linite..."
        curl -L m.linuxuniverse.com.br | bash
        
        # Aguarda conclusão
        while [[ ! -f /srv/system.yaml ]]; do
            sleep 5
        done
    else
        print_status "Sistema Linite já instalado"
    fi
    
    # 2. Localiza arquivo de backup
    print_header "Etapa 2: Localizando backup"
    
    echo "Onde está o arquivo de backup?"
    echo "1) Arquivo local"
    echo "2) Download via URL"
    echo "3) RClone (nuvem)"
    echo "4) Servidor remoto (SCP)"
    read -p "Escolha [1-4]: " backup_source
    
    case $backup_source in
        1)
            read -p "Caminho completo do arquivo: " backup_file
            if [[ ! -f "$backup_file" ]]; then
                print_error "Arquivo não encontrado!"
                exit 1
            fi
            ;;
        2)
            read -p "URL do backup: " backup_url
            print_info "Baixando backup..."
            wget "$backup_url" -O /tmp/backup.tar.gz
            backup_file="/tmp/backup.tar.gz"
            ;;
        3)
            print_info "Remotes disponíveis:"
            rclone listremotes
            read -p "Remote: " remote
            read -p "Caminho no remote: " remote_path
            print_info "Baixando da nuvem..."
            rclone copy "${remote}:${remote_path}" /tmp/
            backup_file="/tmp/$(basename $remote_path)"
            ;;
        4)
            read -p "Servidor (user@host): " remote_server
            read -p "Caminho no servidor: " remote_file
            print_info "Baixando via SCP..."
            scp "${remote_server}:${remote_file}" /tmp/backup.tar.gz
            backup_file="/tmp/backup.tar.gz"
            ;;
    esac
    
    # 3. Valida integridade se houver SHA256
    sha_file="${backup_file%.tar.gz}.sha256"
    if [[ -f "$sha_file" ]]; then
        print_info "Verificando integridade..."
        if sha256sum -c "$sha_file"; then
            print_status "Integridade verificada"
        else
            print_error "Falha na verificação de integridade!"
            read -p "Continuar mesmo assim? (s/N): " -n 1 -r
            echo ""
            [[ ! $REPLY =~ ^[Ss]$ ]] && exit 1
        fi
    fi
    
    # 4. Extrai backup
    print_header "Etapa 3: Extraindo backup"
    TEMP_DIR="/tmp/restore_$$"
    mkdir -p "$TEMP_DIR"
    
    print_info "Extraindo arquivo..."
    tar -xzf "$backup_file" -C "$TEMP_DIR"
    
    # Localiza diretório do backup
    BACKUP_DIR=$(find "$TEMP_DIR" -name "manifest.yaml" -type f | head -1 | xargs dirname)
    
    if [[ -z "$BACKUP_DIR" ]]; then
        print_error "Backup inválido - manifest.yaml não encontrado!"
        exit 1
    fi
    
    # 5. Mostra informações do backup
    print_header "Informações do Backup"
    yq '.backup_info' "$BACKUP_DIR/manifest.yaml"
    echo ""
    
    read -p "Confirma restauração? (s/N): " -n 1 -r
    echo ""
    [[ ! $REPLY =~ ^[Ss]$ ]] && exit 1
    
    # 6. Executa restauração
    restore_system "$BACKUP_DIR"
}

# ================================================================================================
# PROCESSO DE RESTAURAÇÃO
# ================================================================================================

function restore_system() {
    local BACKUP_DIR="$1"
    
    print_header "Iniciando Restauração"
    
    # 1. Para todos os containers
    print_info "Parando containers existentes..."
    docker stop $(docker ps -aq) 2>/dev/null
    
    # 2. Restaura YAMLs primeiro
    print_info "Restaurando configurações YAML..."
    [[ -f "$BACKUP_DIR/configs/system.yaml" ]] && \
        cp "$BACKUP_DIR/configs/system.yaml" /srv/system.yaml
    [[ -f "$BACKUP_DIR/configs/containers.yaml" ]] && \
        cp "$BACKUP_DIR/configs/containers.yaml" /srv/containers.yaml
    
    # 3. Restaura scripts
    print_info "Restaurando scripts..."
    [[ -d "$BACKUP_DIR/configs/scripts" ]] && \
        cp -r "$BACKUP_DIR/configs/scripts"/* /srv/scripts/
    
    # 4. Restaura configurações de rede
    print_info "Restaurando configurações de rede..."
    if [[ -d "$BACKUP_DIR/system/etc/netplan" ]]; then
        # Backup atual
        cp -r /etc/netplan /etc/netplan.bak
        # Restaura
        cp -r "$BACKUP_DIR/system/etc/netplan"/* /etc/netplan/
        print_info "Aplicando configurações de rede..."
        netplan apply
    fi
    
    # 5. Restaura fstab com cuidado
    if [[ -f "$BACKUP_DIR/system/etc/fstab" ]]; then
        print_info "Analisando fstab..."
        cp /etc/fstab /etc/fstab.current
        
        # Mostra diferenças
        echo "Diferenças no fstab:"
        diff /etc/fstab "$BACKUP_DIR/system/etc/fstab" || true
        
        read -p "Aplicar fstab do backup? (s/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            cp "$BACKUP_DIR/system/etc/fstab" /etc/fstab
            mount -a
        fi
    fi
    
    # 6. Recria rede Docker macvlan
    if [[ -f "$BACKUP_DIR/containers/macvlan-network.json" ]]; then
        print_info "Recriando rede macvlan..."
        
        # Remove se existir
        docker network rm macvlan 2>/dev/null
        
        # Extrai configurações
        SUBNET=$(jq -r '.[0].IPAM.Config[0].Subnet' "$BACKUP_DIR/containers/macvlan-network.json")
        GATEWAY=$(jq -r '.[0].IPAM.Config[0].Gateway' "$BACKUP_DIR/containers/macvlan-network.json")
        PARENT=$(jq -r '.[0].Options["parent"]' "$BACKUP_DIR/containers/macvlan-network.json")
        
        # Cria a rede
        docker network create -d macvlan \
            --subnet="$SUBNET" \
            --gateway="$GATEWAY" \
            -o parent="$PARENT" \
            macvlan
        
        print_status "Rede macvlan criada"
    fi
    
    # 7. Restaura volumes dos containers
    print_info "Restaurando volumes dos containers..."
    for volume_file in "$BACKUP_DIR/containers"/*_volumes.tar.gz; do
        if [[ -f "$volume_file" ]]; then
            container_name=$(basename "$volume_file" _volumes.tar.gz)
            print_info "Restaurando volumes de $container_name..."
            mkdir -p /srv/containers
            tar -xzf "$volume_file" -C /srv/containers/
            print_status "Volumes de $container_name restaurados"
        fi
    done
    
    # 8. Recria containers usando o sistema Linite
    print_header "Recriando Containers"
    
    if [[ -f /srv/containers.yaml ]]; then
        # Cria lockfile para modo batch
        touch /srv/lockfile
        
        # Para cada container no YAML
        containers=$(yq -r 'keys | .[]' /srv/containers.yaml)
        
        for container in $containers; do
            print_info "Recriando container: $container"
            
            # Busca a imagem base
            img_base=$(yq -r ".\"$container\".img_base" /srv/containers.yaml)
            
            # Procura script correspondente
            script_path="/srv/scripts/${img_base}.sh"
            if [[ ! -f "$script_path" ]]; then
                # Tenta variações comuns
                for variant in "/srv/scripts/${img_base}" "/srv/scripts/docker-${img_base}" "/srv/scripts/${container}.sh"; do
                    if [[ -f "$variant" ]]; then
                        script_path="$variant"
                        break
                    fi
                done
            fi
            
            if [[ -f "$script_path" ]]; then
                print_info "Executando script: $script_path"
                bash "$script_path"
                print_status "Container $container recriado"
            else
                print_error "Script não encontrado para $container (imagem: $img_base)"
            fi
        done
        
        # Remove lockfile
        rm -f /srv/lockfile
    fi
    
    # 9. Restaura crontabs
    print_info "Restaurando crontabs..."
    if [[ -d "$BACKUP_DIR/system/var/spool/cron/crontabs" ]]; then
        cp -a "$BACKUP_DIR/system/var/spool/cron/crontabs"/* /var/spool/cron/crontabs/
        chmod 600 /var/spool/cron/crontabs/*
        service cron restart
    fi
    
    # 10. Restaura configurações SSH
    print_info "Restaurando SSH..."
    if [[ -d "$BACKUP_DIR/system/etc/ssh" ]]; then
        cp -a "$BACKUP_DIR/system/etc/ssh"/* /etc/ssh/
        service ssh restart
    fi
    
    print_header "Restauração Concluída!"
}

# ================================================================================================
# MODO DE RECUPERAÇÃO SELETIVA
# ================================================================================================

function selective_restore() {
    clear
    echo "╔══════════════════════════════════════╗"
    echo "║  LiniteBackup - Restauração Seletiva ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    
    # Localiza backup
    read -p "Caminho do arquivo de backup: " backup_file
    
    if [[ ! -f "$backup_file" ]]; then
        print_error "Arquivo não encontrado!"
        exit 1
    fi
    
    # Extrai temporariamente
    TEMP_DIR="/tmp/selective_$"
    mkdir -p "$TEMP_DIR"
    tar -xzf "$backup_file" -C "$TEMP_DIR"
    
    BACKUP_DIR=$(find "$TEMP_DIR" -name "manifest.yaml" -type f | head -1 | xargs dirname)
    
    # Menu de seleção
    while true; do
        clear
        echo "O que deseja restaurar?"
        echo ""
        echo "1) Apenas arquivos YAML (system.yaml e containers.yaml)"
        echo "2) Apenas configurações de rede"
        echo "3) Apenas um container específico"
        echo "4) Apenas volumes de containers"
        echo "5) Apenas scripts"
        echo "6) Apenas crontabs"
        echo "7) Lista de pacotes"
        echo "8) Configurações SSH"
        echo "9) Tudo"
        echo "0) Sair"
        echo ""
        read -p "Escolha: " choice
        
        case $choice in
            1)
                print_info "Restaurando YAMLs..."
                [[ -f "$BACKUP_DIR/configs/system.yaml" ]] && \
                    cp "$BACKUP_DIR/configs/system.yaml" /srv/
                [[ -f "$BACKUP_DIR/configs/containers.yaml" ]] && \
                    cp "$BACKUP_DIR/configs/containers.yaml" /srv/
                print_status "YAMLs restaurados"
                ;;
            2)
                print_info "Restaurando configurações de rede..."
                if [[ -d "$BACKUP_DIR/system/etc/netplan" ]]; then
                    cp -r "$BACKUP_DIR/system/etc/netplan"/* /etc/netplan/
                    netplan apply
                fi
                print_status "Rede restaurada"
                ;;
            3)
                # Lista containers disponíveis
                echo "Containers disponíveis no backup:"
                ls "$BACKUP_DIR/containers/"*_volumes.tar.gz 2>/dev/null | \
                    xargs -n1 basename | sed 's/_volumes.tar.gz//'
                
                read -p "Nome do container: " container_name
                
                # Restaura volume
                if [[ -f "$BACKUP_DIR/containers/${container_name}_volumes.tar.gz" ]]; then
                    tar -xzf "$BACKUP_DIR/containers/${container_name}_volumes.tar.gz" \
                        -C /srv/containers/
                    print_status "Container $container_name restaurado"
                else
                    print_error "Container não encontrado"
                fi
                ;;
            4)
                print_info "Restaurando todos os volumes..."
                for volume in "$BACKUP_DIR/containers"/*_volumes.tar.gz; do
                    if [[ -f "$volume" ]]; then
                        tar -xzf "$volume" -C /srv/containers/
                    fi
                done
                print_status "Volumes restaurados"
                ;;
            5)
                print_info "Restaurando scripts..."
                [[ -d "$BACKUP_DIR/configs/scripts" ]] && \
                    cp -r "$BACKUP_DIR/configs/scripts"/* /srv/scripts/
                print_status "Scripts restaurados"
                ;;
            6)
                print_info "Restaurando crontabs..."
                if [[ -d "$BACKUP_DIR/system/var/spool/cron/crontabs" ]]; then
                    cp -a "$BACKUP_DIR/system/var/spool/cron/crontabs"/* \
                        /var/spool/cron/crontabs/
                    chmod 600 /var/spool/cron/crontabs/*
                    service cron restart
                fi
                print_status "Crontabs restaurados"
                ;;
            7)
                if [[ -f "$BACKUP_DIR/system/packages.list" ]]; then
                    cp "$BACKUP_DIR/system/packages.list" /tmp/
                    print_status "Lista salva em /tmp/packages.list"
                    echo "Use: dpkg --set-selections < /tmp/packages.list"
                fi
                ;;
            8)
                print_info "Restaurando SSH..."
                if [[ -d "$BACKUP_DIR/system/etc/ssh" ]]; then
                    cp -a "$BACKUP_DIR/system/etc/ssh"/* /etc/ssh/
                    service ssh restart
                fi
                print_status "SSH restaurado"
                ;;
            9)
                restore_system "$BACKUP_DIR"
                break
                ;;
            0)
                break
                ;;
        esac
        
        read -p "Pressione Enter para continuar..."
    done
    
    # Limpa
    rm -rf "$TEMP_DIR"
}

# ================================================================================================
# VERIFICAÇÃO DE SAÚDE DO BACKUP
# ================================================================================================

function verify_backup() {
    clear
    echo "╔══════════════════════════════════════╗"
    echo "║  LiniteBackup - Verificação          ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    
    read -p "Caminho do arquivo de backup: " backup_file
    
    if [[ ! -f "$backup_file" ]]; then
        print_error "Arquivo não encontrado!"
        exit 1
    fi
    
    # Verifica integridade
    sha_file="${backup_file%.tar.gz}.sha256"
    if [[ -f "$sha_file" ]]; then
        print_info "Verificando integridade SHA256..."
        if sha256sum -c "$sha_file"; then
            print_status "Integridade OK"
        else
            print_error "Integridade comprometida!"
        fi
    else
        print_info "Arquivo SHA256 não encontrado"
    fi
    
    # Lista conteúdo
    print_info "Conteúdo do backup:"
    tar -tzf "$backup_file" | head -20
    echo "..."
    
    # Extrai e analisa manifest
    TEMP_DIR="/tmp/verify_$"
    mkdir -p "$TEMP_DIR"
    tar -xzf "$backup_file" --wildcards "*/manifest.yaml" -C "$TEMP_DIR" 2>/dev/null
    
    manifest=$(find "$TEMP_DIR" -name "manifest.yaml" -type f | head -1)
    if [[ -f "$manifest" ]]; then
        print_info "Informações do Backup:"
        yq '.' "$manifest"
    fi
    
    # Limpa
    rm -rf "$TEMP_DIR"
}

# ================================================================================================
# MENU PRINCIPAL
# ================================================================================================

function main_menu() {
    while true; do
        clear
        echo "╔══════════════════════════════════════╗"
        echo "║     LiniteBackup - Restauração       ║"
        echo "║           Versão 1.0                 ║"
        echo "╚══════════════════════════════════════╝"
        echo ""
        echo "1) Restauração completa em servidor novo"
        echo "2) Restauração seletiva"
        echo "3) Verificar integridade do backup"
        echo "4) Sair"
        echo ""
        read -p "Escolha [1-4]: " choice
        
        case $choice in
            1) prepare_new_server ;;
            2) selective_restore ;;
            3) verify_backup ;;
            4) exit 0 ;;
            *) print_error "Opção inválida" ;;
        esac
    done
}

# Verifica se é root
if [[ $EUID -ne 0 ]]; then
    print_error "Este script deve ser executado como root!"
    exit 1
fi

# Executa
main_menu
