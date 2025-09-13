
#!/bin/bash

# ================================================================================================
# LiniteBackup - Menu Integrado
# Adicionar ao menu SRV do Linite
# ================================================================================================

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# ================================================================================================
# INSTALAÇÃO NO SISTEMA LINITE
# ================================================================================================

function install_linite_backup() {
    echo -e "${BLUE}Instalando LiniteBackup no sistema...${NC}"
    
    # Cria diretórios
    sudo mkdir -p /srv/scripts/backup
    sudo mkdir -p /srv/backup
    
    # Baixa scripts
    echo "Baixando scripts de backup..."
    
    # Script de backup completo
    sudo wget -O /srv/scripts/backup/backup-full.sh \
        "https://raw.githubusercontent.com/urbancompasspony/linite-backup/main/backup-full.sh"
    
    # Script de restauração
    sudo wget -O /srv/scripts/backup/restore-full.sh \
        "https://raw.githubusercontent.com/urbancompasspony/linite-backup/main/restore-full.sh"
    
    # Torna executáveis
    sudo chmod +x /srv/scripts/backup/*.sh
    
    # Adiciona ao crontab (backup diário às 3h)
    (sudo crontab -l 2>/dev/null; echo "") | sudo crontab -
    (sudo crontab -l 2>/dev/null; echo "# LiniteBackup - Backup Automático") | sudo crontab -
    (sudo crontab -l 2>/dev/null; echo "0 3 * * * /srv/scripts/backup/backup-full.sh > /var/log/linite-backup.log 2>&1") | sudo crontab -
    
    # Atualiza YAML
    sudo yq -i ".Backup.LiniteBackup = \"Instalado\"" /srv/system.yaml
    sudo yq -i ".Backup.Versao = \"1.0\"" /srv/system.yaml
    sudo yq -i ".Backup.UltimoBackup = \"Nunca\"" /srv/system.yaml
    
    echo -e "${GREEN}LiniteBackup instalado com sucesso!${NC}"
}

# ================================================================================================
# MENU PRINCIPAL DO BACKUP
# ================================================================================================

function backup_menu() {
    while true; do
        clear
        echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║     LiniteBackup - Menu Principal    ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
        echo ""
        
        # Verifica status
        if [[ -f /srv/scripts/backup/backup-full.sh ]]; then
            echo -e "${GREEN}Status: Instalado${NC}"
        else
            echo -e "${RED}Status: Não instalado${NC}"
        fi
        
        # Mostra último backup
        if [[ -f /srv/system.yaml ]]; then
            ultimo=$(yq '.Backup.UltimoBackup' /srv/system.yaml 2>/dev/null)
            echo -e "Último backup: ${YELLOW}$ultimo${NC}"
        fi
        
        echo ""
        echo "1) Fazer backup completo agora"
        echo "2) Restaurar backup"
        echo "3) Configurar backup automático"
        echo "4) Verificar backups existentes"
        echo "5) Backup para nuvem"
        echo "6) Instalar/Atualizar LiniteBackup"
        echo "7) Desinstalar LiniteBackup"
        echo "0) Voltar"
        echo ""
        read -p "Escolha: " choice
        
        case $choice in
            1) backup_now ;;
            2) restore_menu ;;
            3) configure_auto_backup ;;
            4) list_backups ;;
            5) cloud_backup_menu ;;
            6) install_linite_backup ;;
            7) uninstall_linite_backup ;;
            0) return ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 2 ;;
        esac
    done
}

# ================================================================================================
# FUNÇÕES DO MENU
# ================================================================================================

function backup_now() {
    clear
    echo -e "${BLUE}Executando backup completo...${NC}"
    echo ""
    
    # Executa o backup
    if [[ -f /srv/scripts/backup/backup-full.sh ]]; then
        sudo /srv/scripts/backup/backup-full.sh
        
        # Atualiza YAML com data do último backup
        sudo yq -i ".Backup.UltimoBackup = \"$(date +'%d/%m/%Y %H:%M')\"" /srv/system.yaml
        
        echo ""
        echo -e "${GREEN}Backup concluído!${NC}"
    else
        echo -e "${RED}Script de backup não encontrado!${NC}"
        echo "Execute a instalação primeiro (opção 6)"
    fi
    
    read -p "Pressione Enter para continuar..."
}

function restore_menu() {
    clear
    echo -e "${BLUE}Menu de Restauração${NC}"
    echo ""
    echo "1) Restaurar de arquivo local"
    echo "2) Restaurar da nuvem"
    echo "3) Restauração seletiva"
    echo "0) Voltar"
    echo ""
    read -p "Escolha: " choice
    
    case $choice in
        1)
            read -p "Caminho do backup: " backup_path
            if [[ -f "$backup_path" ]]; then
                sudo /srv/scripts/backup/restore-full.sh "$backup_path"
            else
                echo -e "${RED}Arquivo não encontrado!${NC}"
            fi
            ;;
        2)
            cloud_restore
            ;;
        3)
            selective_restore_menu
            ;;
        0)
            return
            ;;
    esac
    
    read -p "Pressione Enter para continuar..."
}

function configure_auto_backup() {
    clear
    echo -e "${BLUE}Configuração de Backup Automático${NC}"
    echo ""
    echo "Configuração atual:"
    sudo crontab -l | grep LiniteBackup -A1 | grep -v "^#"
    echo ""
    echo "1) Backup diário às 3h"
    echo "2) Backup semanal (domingos às 3h)"
    echo "3) Backup mensal (dia 1 às 3h)"
    echo "4) Personalizar horário"
    echo "5) Desativar backup automático"
    echo "0) Voltar"
    echo ""
    read -p "Escolha: " choice
    
    # Remove entrada atual
    sudo crontab -l | grep -v "LiniteBackup" | grep -v "backup-full.sh" | sudo crontab -
    
    case $choice in
        1)
            (sudo crontab -l 2>/dev/null; echo "# LiniteBackup - Backup Automático") | sudo crontab -
            (sudo crontab -l 2>/dev/null; echo "0 3 * * * /srv/scripts/backup/backup-full.sh > /var/log/linite-backup.log 2>&1") | sudo crontab -
            echo -e "${GREEN}Backup diário configurado${NC}"
            ;;
        2)
            (sudo crontab -l 2>/dev/null; echo "# LiniteBackup - Backup Automático") | sudo crontab -
            (sudo crontab -l 2>/dev/null; echo "0 3 * * 0 /srv/scripts/backup/backup-full.sh > /var/log/linite-backup.log 2>&1") | sudo crontab -
            echo -e "${GREEN}Backup semanal configurado${NC}"
            ;;
        3)
            (sudo crontab -l 2>/dev/null; echo "# LiniteBackup - Backup Automático") | sudo crontab -
            (sudo crontab -l 2>/dev/null; echo "0 3 1 * * /srv/scripts/backup/backup-full.sh > /var/log/linite-backup.log 2>&1") | sudo crontab -
            echo -e "${GREEN}Backup mensal configurado${NC}"
            ;;
        4)
            echo "Formato: minuto hora dia mês dia_semana"
            echo "Exemplo: 30 2 * * * (todos os dias às 2:30)"
            read -p "Digite o agendamento: " schedule
            (sudo crontab -l 2>/dev/null; echo "# LiniteBackup - Backup Automático") | sudo crontab -
            (sudo crontab -l 2>/dev/null; echo "$schedule /srv/scripts/backup/backup-full.sh > /var/log/linite-backup.log 2>&1") | sudo crontab -
            echo -e "${GREEN}Backup personalizado configurado${NC}"
            ;;
        5)
            echo -e "${YELLOW}Backup automático desativado${NC}"
            ;;
    esac
    
    read -p "Pressione Enter para continuar..."
}

function list_backups() {
    clear
    echo -e "${BLUE}Backups Existentes${NC}"
    echo ""
    
    if [[ -d /srv/backup ]]; then
        echo "Local: /srv/backup"
        ls -lh /srv/backup/*.tar.gz 2>/dev/null | awk '{print $9, $5}' | column -t
        
        echo ""
        echo "Espaço usado:"
        du -sh /srv/backup
    else
        echo -e "${YELLOW}Nenhum backup encontrado${NC}"
    fi
    
    echo ""
    read -p "Pressione Enter para continuar..."
}

function cloud_backup_menu() {
    clear
    echo -e "${BLUE}Backup para Nuvem${NC}"
    echo ""
    
    # Verifica se rclone está configurado
    if ! command -v rclone &> /dev/null; then
        echo -e "${RED}RClone não está instalado!${NC}"
        echo "Instale com: sudo apt install rclone"
        read -p "Pressione Enter para continuar..."
        return
    fi
    
    # Lista remotes
    echo "Remotes configurados:"
    rclone listremotes
    
    if [[ $(rclone listremotes | wc -l) -eq 0 ]]; then
        echo -e "${YELLOW}Nenhum remote configurado${NC}"
        echo "Configure com: rclone config"
    else
        echo ""
        echo "1) Fazer backup para nuvem agora"
        echo "2) Configurar backup automático para nuvem"
        echo "3) Listar backups na nuvem"
        echo "0) Voltar"
        echo ""
        read -p "Escolha: " choice
        
        case $choice in
            1)
                read -p "Nome do remote: " remote
                echo "Fazendo backup para $remote..."
                # Faz backup local primeiro
                sudo /srv/scripts/backup/backup-full.sh
                # Envia para nuvem
                latest=$(ls -t /srv/backup/*.tar.gz | head -1)
                rclone copy "$latest" "${remote}:LiniteBackups/" --progress
                echo -e "${GREEN}Backup enviado para nuvem${NC}"
                ;;
            2)
                read -p "Nome do remote: " remote
                # Adiciona ao crontab
                (sudo crontab -l 2>/dev/null; echo "# LiniteBackup - Upload para Nuvem") | sudo crontab -
                (sudo crontab -l 2>/dev/null; echo "30 3 * * * rclone copy /srv/backup/*.tar.gz ${remote}:LiniteBackups/ --min-age 1h") | sudo crontab -
                echo -e "${GREEN}Upload automático configurado${NC}"
                ;;
            3)
                read -p "Nome do remote: " remote
                echo "Backups em ${remote}:LiniteBackups/"
                rclone ls "${remote}:LiniteBackups/" | grep tar.gz
                ;;
        esac
    fi
    
    read -p "Pressione Enter para continuar..."
}

function uninstall_linite_backup() {
    clear
    echo -e "${RED}Desinstalar LiniteBackup${NC}"
    echo ""
    echo "Isso irá remover os scripts mas NÃO os backups existentes."
    read -p "Confirma? (s/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        # Remove scripts
        sudo rm -rf /srv/scripts/backup
        
        # Remove do crontab
        sudo crontab -l | grep -v "LiniteBackup" | grep -v "backup-full.sh" | sudo crontab -
        
        # Atualiza YAML
        sudo yq -i "del(.Backup)" /srv/system.yaml
        
        echo -e "${GREEN}LiniteBackup desinstalado${NC}"
    else
        echo "Operação cancelada"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# ================================================================================================
# INTEGRAÇÃO COM MENU SRV
# ================================================================================================

# Esta função deve ser chamada do menu principal do Linite
function linite_backup_integration() {
    # Verifica se está instalado
    if [[ ! -f /srv/scripts/backup/backup-full.sh ]]; then
        echo -e "${YELLOW}LiniteBackup não está instalado${NC}"
        echo "Deseja instalar agora? (s/N): "
        read -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            install_linite_backup
        fi
    fi
    
    # Abre menu principal
    backup_menu
}

# Se executado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Verifica root
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Execute como root!${NC}"
        exit 1
    fi
    
    linite_backup_integration
fi
