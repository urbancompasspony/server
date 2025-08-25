#!/bin/bash
# Script para busca rápida usando locate em backups rsnapshot

# Configurações
LOCATE_DB="/var/lib/plocate/plocate.db"
SYSLOG_PATH="/srv/containers/dominio/log/syslog"

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

# Função para coletar todos os caminhos únicos
collect_all_paths() {
    local paths=()
    local RSNAPSHOT_CONFIGS=($(find_rsnapshot_configs))
    
    for config in "${RSNAPSHOT_CONFIGS[@]}"; do
        # Adicionar snapshot_root
        local snapshot_root=$(extract_snapshot_root "$config")
        if [ -n "$snapshot_root" ] && [ -d "$snapshot_root" ]; then
            paths+=("$snapshot_root")
        fi
        
        # Adicionar backup paths
        local backup_paths=$(extract_backup_paths "$config")
        while IFS= read -r path; do
            if [ -n "$path" ] && [ -d "$path" ]; then
                paths+=("$path")
            fi
        done <<< "$backup_paths"
    done
    
    # Remover duplicatas e retornar
    printf '%s\n' "${paths[@]}" | sort -u
}

# Função para verificar e criar índice
check_and_create_index() {
    local paths=($(collect_all_paths))
    
    if [ ${#paths[@]} -eq 0 ]; then
        echo "❌ Nenhum caminho de backup encontrado!"
        return 1
    fi
    
    # Verificar se o banco existe e não está muito antigo (mais de 1 dia)
    if [ ! -f "$LOCATE_DB" ] || [ $(find "$LOCATE_DB" -mtime +1 2>/dev/null | wc -l) -gt 0 ]; then
        echo "🔄 Criando/atualizando índice do locate..."
        echo "📁 Caminhos que serão indexados:"
        for path in "${paths[@]}"; do
            echo "   - $path"
        done
        echo
        
        # Criar string de caminhos separados por espaço
        local paths_string=""
        for path in "${paths[@]}"; do
            paths_string="$paths_string $path"
        done
        
        echo "⏳ Indexando... (isso pode demorar alguns minutos)"
        sudo updatedb --localpaths="$paths_string" --database-root="$LOCATE_DB"
        
        if [ $? -eq 0 ]; then
            echo "✅ Índice criado com sucesso!"
        else
            echo "❌ Erro ao criar índice!"
            return 1
        fi
        echo
    else
        echo "✅ Índice do locate já existe e está atualizado"
        echo
    fi
}

# Função para buscar com locate
search_with_locate() {
    local search_term="$1"
    local results_found=0
    
    echo "🔍 Buscando arquivos e pastas com locate..."
    echo "⚡ Termo: $search_term"
    echo
    
    # Buscar com diferentes padrões
    local patterns=("*$search_term*" "*${search_term,,}*" "*${search_term^^}*")
    
    for pattern in "${patterns[@]}"; do
        local results=$(locate --database="$LOCATE_DB" "$pattern" 2>/dev/null)
        if [ -n "$results" ]; then
            if [ $results_found -eq 0 ]; then
                echo "📋 Resultados encontrados:"
            fi
            echo "$results"
            results_found=1
        fi
    done
    
    if [ $results_found -eq 0 ]; then
        echo "ℹ️  Nenhum arquivo/pasta encontrado com locate"
        echo "💡 Dica: O índice pode estar desatualizado. Execute o script novamente para recriar."
    fi
    echo
}

# Função para buscar no syslog
search_in_syslog() {
    local search_term="$1"
    
    echo "📁 Buscando nos logs do sistema:"
    echo "   $SYSLOG_PATH"
    
    if [ -f "$SYSLOG_PATH" ]; then
        echo "   Resultados encontrados no syslog:"
        local syslog_results=$(grep -i "$search_term" "$SYSLOG_PATH" 2>/dev/null | head -20)
        if [ -n "$syslog_results" ]; then
            echo "$syslog_results"
        else
            echo "   ℹ️  Nenhum resultado encontrado no syslog"
        fi
    else
        echo "   ⚠️  Arquivo de syslog não encontrado: $SYSLOG_PATH"
    fi
    echo
}

# Função para mostrar estatísticas do índice
show_index_stats() {
    if [ -f "$LOCATE_DB" ]; then
        local count=$(locate --database="$LOCATE_DB" "*" 2>/dev/null | wc -l)
        local size=$(du -h "$LOCATE_DB" 2>/dev/null | cut -f1)
        local modified=$(stat -c '%y' "$LOCATE_DB" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
        
        echo "📊 Estatísticas do índice:"
        echo "   Arquivos indexados: $count"
        echo "   Tamanho do banco: $size"
        echo "   Última atualização: $modified"
        echo
    fi
}

# ==================== MAIN ====================

# Se não foi passado argumento, perguntar interativamente
if [ -z "$1" ]; then
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║            BUSCA RÁPIDA EM RSNAPSHOT / SAMBA AD BACKUP          ║"
    echo "║                      (Powered by locate)                        ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo
    echo "🚀 Busca super rápida usando índice do locate!"
    echo "📂 As buscas serão realizadas em:"
    echo "   • Backups RSnapshots (arquivos e pastas)"
    echo "   • Logs do SAMBA-AD (conteúdo de arquivos)"
    echo
    echo "💡 Para termos com espaços: \"azul engenharia\""
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

echo "=========================================="

# Verificar se rsnapshot configs existem
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
    echo "   - $(basename "$config")"
done
echo

# Verificar e criar/atualizar índice
check_and_create_index
if [ $? -ne 0 ]; then
    echo "❌ Não foi possível criar o índice. Abortando..."
    exit 1
fi

# Mostrar estatísticas
show_index_stats

# Processar termo de busca
if [[ "$SEARCH_NAME" == *" "* ]]; then
    SEARCH_PATTERN="$SEARCH_NAME"
    echo "🔍 Buscando por: \"$SEARCH_PATTERN\" (termo com espaços)"
else
    SEARCH_PATTERN="$SEARCH_NAME"
    echo "🔍 Buscando por: $SEARCH_PATTERN"
fi
echo

# Executar busca com locate
search_with_locate "$SEARCH_PATTERN"

# Executar busca no syslog (locate não busca conteúdo de arquivos)
search_in_syslog "$SEARCH_PATTERN"

echo "=========================================="
echo "✅ Busca concluída!"
echo "⚡ Tempo de resposta: Super rápido com locate!"
echo "💾 Banco de dados: $LOCATE_DB"
echo
echo "💡 Dicas:"
echo "   • Para recriar o índice: sudo rm $LOCATE_DB"
echo "   • Para busca em tempo real: use o script original com find"
echo
read -p "Pressione Enter para voltar ao menu..." -t 30
