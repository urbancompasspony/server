#!/bin/bash

# Script para extrair caminhos do rsnapshot.conf e buscar arquivos/pastas

if [ -f /srv/scripts/rsnapshot ]; then
  clear; echo "Encontrei o Rsnapshot CDN!"
  RSNAPSHOT_CONFIG="/srv/scripts/rsnapshot"
else
  clear; echo "Fallback procurando rsnapshot do modelo antigo"
  RSNAPSHOT_CONFIG="/srv/containers/scripts/rsnapshot"
fi

# Se não foi passado argumento, perguntar interativamente
if [ -z "$1" ]; then
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    BUSCA EM RSNAPSHOT BACKUP                   ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo
    echo "Digite o termo que deseja buscar:"
    echo "💡 Para termos com espaços: azul engenharia"
    echo "💡 Para uma palavra: arquivo"
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

# Função para extrair snapshot_root
extract_snapshot_root() {
    grep -E "^snapshot_root\s+" "$RSNAPSHOT_CONFIG" | sed -E 's/^snapshot_root\s+(.+)$/\1/' | tr -d '\t'
}

# Função para extrair caminhos de backup
extract_backup_paths() {
    grep -E "^backup\s+" "$RSNAPSHOT_CONFIG" | sed -E 's/^backup\s+([^\t]+)\t.*/\1/' | tr -d '\t'
}

# Extrair snapshot_root
SNAPSHOT_ROOT=$(extract_snapshot_root)
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
BACKUP_PATHS=$(extract_backup_paths)
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

# Buscar também nos logs do syslog
SYSLOG_PATH="/srv/containers/dominio/log/syslog"
if [ -f "$SYSLOG_PATH" ]; then
    echo "📁 Buscando nos logs do sistema:"
    echo "   $SYSLOG_PATH"
    echo "   Resultados encontrados no syslog:"
    grep -i "$SEARCH_NAME" "$SYSLOG_PATH" 2>/dev/null || echo "   ℹ️  Nenhum resultado encontrado no syslog"
    echo
fi

# Regex patterns utilizados (para referência)
echo "=========================================="
echo "✅ Busca concluída!"
echo
read -p "Pressione Enter para voltar ao menu..." -t 30
