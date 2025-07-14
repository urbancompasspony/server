#!/bin/bash
# Script para extrair caminhos do rsnapshot.conf e buscar arquivos/pastas

# Função para buscar todos os arquivos rsnapshot
find_rsnapshot_configs() {
    local configs=()
    
    # Buscar em /srv/scripts/
    if [ -d "/srv/scripts" ]; then
        while IFS= read -r -d '' file; do
            configs+=("$file")
        done < <(find /srv/scripts -maxdepth 1 -name "rsnapshot*" -type f -print0 2>/dev/null)
    fi
    
    # Buscar em /srv/containers/scripts/
    if [ -d "/srv/containers/scripts" ]; then
        while IFS= read -r -d '' file; do
            configs+=("$file")
        done < <(find /srv/containers/scripts -maxdepth 1 -name "rsnapshot*" -type f -print0 2>/dev/null)
    fi
    
    printf '%s\n' "${configs[@]}"
}

# Se não foi passado argumento, perguntar interativamente
if [ -z "$1" ]; then
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                BUSCA EM RSNAPSHOT / SAMBA AD BACKUP              ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo
    echo "As buscas serão realizadas dentro do arquivo de Log do SAMBA-AD e também dos backups RSnapshots (se existentes)"
    echo ""
    echo "💡 Para termos com espaços, conforme exemplo: azul engenharia"
    echo "💡 Para uma única palavra: arquivo"
    echo
    
    # Força redirecionamento para /dev/tty para funcionar dentro de dialog
    exec < /dev/tty
    read -p "🔍 Termo: " SEARCH_NAME
    
    # Verificar se o usuário digitou algo
    if [ -z "$SEARCH_NAME" ]; then
        echo "❌ Nenhum termo foi digitado. Saindo..."
        read -p "Pressione Enter para continuar..."
        exit 1
    fi
else
    SEARCH_NAME="$1"
fi

# Verificar se o termo tem espaços e ajustar para busca
if [[ "$SEARCH_NAME" == *" "* ]]; then
    SEARCH_PATTERN="'$SEARCH_NAME'"
    echo "Buscando por: $SEARCH_PATTERN (termo com espaços)"
else
    SEARCH_PATTERN="$SEARCH_NAME"
    echo "Buscando por: $SEARCH_PATTERN"
fi

echo "=========================================="

# Encontrar todos os arquivos rsnapshot
RSNAPSHOT_CONFIGS=($(find_rsnapshot_configs))

if [ ${#RSNAPSHOT_CONFIGS[@]} -eq 0 ]; then
    echo "❌ Nenhum arquivo rsnapshot encontrado!"
    echo "   Procurado em:"
    echo "   - /srv/scripts/rsnapshot*"
    echo "   - /srv/containers/scripts/rsnapshot*"
    exit 1
fi

echo "📋 Arquivos rsnapshot encontrados:"
for config in "${RSNAPSHOT_CONFIGS[@]}"; do
    echo "   - $config"
done
echo

# Função para extrair snapshot_root
extract_snapshot_root() {
    local config_file="$1"
    grep -E "^snapshot_root\s+" "$config_file" | sed -E 's/^snapshot_root\s+(.+)$/\1/' | tr -d '\t'
}

# Função para extrair caminhos de backup
extract_backup_paths() {
    local config_file="$1"
    grep -E "^backup\s+" "$config_file" | sed -E 's/^backup\s+([^\t]+)\t.*/\1/' | tr -d '\t'
}

# Processar cada arquivo rsnapshot encontrado
for RSNAPSHOT_CONFIG in "${RSNAPSHOT_CONFIGS[@]}"; do
    echo "🔧 Processando: $(basename "$RSNAPSHOT_CONFIG")"
    echo "   Arquivo: $RSNAPSHOT_CONFIG"
    echo
    
    # Extrair snapshot_root
    SNAPSHOT_ROOT=$(extract_snapshot_root "$RSNAPSHOT_CONFIG")
    if [ -n "$SNAPSHOT_ROOT" ]; then
        echo "📁 Snapshot Root: $SNAPSHOT_ROOT"
        if [ -d "$SNAPSHOT_ROOT" ]; then
            echo "   Buscando em $SNAPSHOT_ROOT..."
            find "$SNAPSHOT_ROOT" -type f -name "*$SEARCH_NAME*" -o -type d -name "*$SEARCH_NAME*" 2>/dev/null
        else
            echo "   ⚠️  Diretório não encontrado: $SNAPSHOT_ROOT"
        fi
        echo
    fi
    
    # Extrair e buscar em caminhos de backup
    BACKUP_PATHS=$(extract_backup_paths "$RSNAPSHOT_CONFIG")
    if [ -n "$BACKUP_PATHS" ]; then
        echo "📁 Caminhos de Backup:"
        while IFS= read -r path; do
            if [ -n "$path" ]; then
                echo "   $path"
                if [ -d "$path" ]; then
                    echo "   Buscando em $path..."
                    find "$path" -type f -name "*$SEARCH_NAME*" -o -type d -name "*$SEARCH_NAME*" 2>/dev/null
                else
                    echo "   ⚠️  Diretório não encontrado: $path"
                fi
                echo
            fi
        done <<< "$BACKUP_PATHS"
    fi
    
    echo "────────────────────────────────────────"
done

# Buscar também nos logs do syslog
SYSLOG_PATH="/srv/containers/dominio/log/syslog"
if [ -f "$SYSLOG_PATH" ]; then
    echo "📁 Buscando nos logs do sistema:"
    echo "   $SYSLOG_PATH"
    echo "   Resultados encontrados no syslog:"
    grep -i "$SEARCH_NAME" "$SYSLOG_PATH" 2>/dev/null || echo "   ℹ️  Nenhum resultado encontrado no syslog"
    echo
fi

echo "=========================================="
echo "✅ Busca concluída!"
echo "📊 Resumo: Processados ${#RSNAPSHOT_CONFIGS[@]} arquivo(s) rsnapshot"
echo
read -p "Pressione Enter para voltar ao menu..." -t 30
