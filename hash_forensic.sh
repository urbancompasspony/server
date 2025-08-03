#!/bin/bash

# Script de Verificação de Integridade usando NSRL e ferramentas forenses
# Autor: Sistema de Auditoria de Segurança
# Data: $(date)

# Configurações
LOG_DIR="/var/log/forensic-audit"
TEMP_DIR="/tmp/forensic-temp"
CIRCL_API_BASE="https://hashlookup.circl.lu"
SUSPICIOUS_LOG="$LOG_DIR/suspicious_files.log"
REPORT_FILE="$LOG_DIR/audit_report_$(date +%Y%m%d_%H%M%S).txt"
KNOWN_GOOD_DB="$LOG_DIR/known_good_hashes.db"
BLACKLIST_DB="$LOG_DIR/blacklist_hashes.db"
BULK_HASH_FILE="$TEMP_DIR/bulk_hashes.json"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Função para log
log_message() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$REPORT_FILE"
}

# Função para criar diretórios necessários
setup_environment() {
    mkdir -p "$LOG_DIR" "$TEMP_DIR"
    log_message "${GREEN}[INFO]${NC} Ambiente configurado"
}

# Função para testar conectividade com CIRCL API
test_circl_connectivity() {
    log_message "${YELLOW}[INFO]${NC} Testando conectividade com CIRCL API..."

    local info_response=$(curl -s -f --connect-timeout 10 --max-time 15 "$CIRCL_API_BASE/info" 2>/dev/null)

    if [ $? -eq 0 ]; then
        log_message "${GREEN}[SUCCESS]${NC} CIRCL API acessível"
        log_message "Info da API: $info_response"
        return 0
    else
        log_message "${RED}[ERROR]${NC} CIRCL API não acessível"
        return 1
    fi
}

# Função para verificar hash individual no CIRCL
check_single_hash_circl() {
    local hash_value="$1"
    local file_path="$2"
    local hash_type="sha1"  # Padrão SHA1

    # Detectar tipo de hash baseado no comprimento
    case ${#hash_value} in
        32) hash_type="md5" ;;
        40) hash_type="sha1" ;;
        64) hash_type="sha256" ;;
        *)
            log_message "${YELLOW}[WARNING]${NC} Tipo de hash não reconhecido para $file_path"
            return 1
            ;;
    esac

    local endpoint="$CIRCL_API_BASE/lookup/$hash_type/$hash_value"
    local response=$(curl -s -f --connect-timeout 5 --max-time 10 "$endpoint" 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$response" ]; then
        # Parse da resposta JSON para extrair informações úteis
        local filename=$(echo "$response" | grep -o '"FileName":"[^"]*"' | cut -d'"' -f4 2>/dev/null)
        local source=$(echo "$response" | grep -o '"source":"[^"]*"' | cut -d'"' -f4 2>/dev/null)

        log_message "${GREEN}[KNOWN-CIRCL]${NC} $file_path"
        log_message "  Hash encontrado: $hash_type:$hash_value"
        [ -n "$filename" ] && log_message "  Nome original: $filename"
        [ -n "$source" ] && log_message "  Fonte: $source"

        # Adicionar à base local para cache
        echo "$hash_value|$file_path|$(date)|KNOWN|$source" >> "$KNOWN_GOOD_DB"
        return 0
    else
        log_message "${RED}[SUSPICIOUS]${NC} $file_path - Hash $hash_type:$hash_value NÃO encontrado"
        echo "$file_path|$hash_value|$(date)|NOT_FOUND|$hash_type" >> "$SUSPICIOUS_LOG"
        return 1
    fi
}

# Função para verificação em lote usando bulk endpoints
check_bulk_hashes_circl() {
    local hash_file="$1"
    local hash_type="$2"

    log_message "${YELLOW}[INFO]${NC} Preparando verificação em lote ($hash_type)..."

    # Preparar JSON para bulk check
    local hashes_array="["
    local first=true

    while read -r hash_value file_path; do
        if [ "$first" = true ]; then
            first=false
        else
            hashes_array+=","
        fi
        hashes_array+="\"$hash_value\""
    done < "$hash_file"

    hashes_array+="]"

    # Criar JSON payload
    echo "{\"hashes\": $hashes_array}" > "$BULK_HASH_FILE"

    # Fazer requisição bulk
    local endpoint="$CIRCL_API_BASE/bulk/$hash_type"
    local response=$(curl -s -f --connect-timeout 30 --max-time 60 \
        -H "Content-Type: application/json" \
        -d @"$BULK_HASH_FILE" \
        "$endpoint" 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$response" ]; then
        log_message "${GREEN}[SUCCESS]${NC} Verificação em lote concluída"

        # Processar resposta bulk
        process_bulk_response "$response" "$hash_file"
        return 0
    else
        log_message "${YELLOW}[WARNING]${NC} Verificação em lote falhou, usando verificação individual"
        return 1
    fi
}

# Função para processar resposta da verificação em lote
process_bulk_response() {
    local response="$1"
    local hash_file="$2"

    # Criar arquivo temporário com os resultados
    local results_file="$TEMP_DIR/bulk_results.tmp"
    echo "$response" > "$results_file"

    # Processar cada hash do arquivo original
    while read -r hash_value file_path; do
        # Verificar se o hash está na resposta
        if grep -q "\"$hash_value\"" "$results_file" 2>/dev/null; then
            # Extrair informações do hash encontrado
            local hash_info=$(echo "$response" | grep -A 10 -B 2 "\"$hash_value\"" 2>/dev/null)
            local source=$(echo "$hash_info" | grep -o '"source":"[^"]*"' | cut -d'"' -f4 2>/dev/null | head -1)

            log_message "${GREEN}[KNOWN-BULK]${NC} $file_path"
            [ -n "$source" ] && log_message "  Fonte: $source"

            echo "$hash_value|$file_path|$(date)|KNOWN|$source" >> "$KNOWN_GOOD_DB"
        else
            log_message "${RED}[SUSPICIOUS-BULK]${NC} $file_path - Hash não encontrado"
            echo "$file_path|$hash_value|$(date)|NOT_FOUND|bulk" >> "$SUSPICIOUS_LOG"
        fi
    done < "$hash_file"

    rm -f "$results_file"
}

# Função para verificar hash em base local de conhecidos-bons
check_hash_local_good() {
    local hash_value="$1"
    local file_path="$2"

    if [ -f "$KNOWN_GOOD_DB" ]; then
        if grep -q "^$hash_value" "$KNOWN_GOOD_DB" 2>/dev/null; then
            log_message "${GREEN}[KNOWN-LOCAL]${NC} $file_path - Hash em lista local de conhecidos-bons"
            return 0
        fi
    fi

    return 1
}

# Função para verificar hash em blacklist local
check_hash_blacklist() {
    local hash_value="$1"
    local file_path="$2"

    if [ -f "$BLACKLIST_DB" ]; then
        if grep -q "^$hash_value" "$BLACKLIST_DB" 2>/dev/null; then
            log_message "${RED}[BLACKLISTED]${NC} $file_path - Hash em blacklist local!"
            echo "$file_path|$hash_value|$(date)|BLACKLISTED" >> "$SUSPICIOUS_LOG"
            return 0
        fi
    fi

    return 1
}

# Função para verificar hash com múltiplas estratégias
check_hash_comprehensive() {
    local hash_value="$1"
    local file_path="$2"

    # 1. Verificar primeiro em blacklist local
    if check_hash_blacklist "$hash_value" "$file_path"; then
        return 2  # Código especial para blacklisted
    fi

    # 2. Verificar em cache local de conhecidos-bons
    if check_hash_local_good "$hash_value" "$file_path"; then
        return 0
    fi

    # 3. Verificar no CIRCL hashlookup
    if check_single_hash_circl "$hash_value" "$file_path"; then
        return 0
    fi

    # Se chegou aqui, o hash não foi encontrado em nenhuma base
    return 1
}

# Função otimizada para calcular múltiplos tipos de hash
calculate_file_hashes_multi() {
    local target_path="$1"
    local hash_file_md5="$TEMP_DIR/file_hashes_md5.txt"
    local hash_file_sha1="$TEMP_DIR/file_hashes_sha1.txt"
    local hash_file_sha256="$TEMP_DIR/file_hashes_sha256.txt"

    log_message "${YELLOW}[INFO]${NC} Calculando hashes (MD5, SHA1, SHA256) para: $target_path"

    # Limpar arquivos anteriores
    > "$hash_file_md5"
    > "$hash_file_sha1"
    > "$hash_file_sha256"

    # Usar find com exec para processar arquivos de forma eficiente
    find "$target_path" -type f -print0 | while IFS= read -r -d '' file; do
        if [ -r "$file" ]; then
            local md5_hash=$(md5sum "$file" 2>/dev/null | cut -d' ' -f1)
            local sha1_hash=$(sha1sum "$file" 2>/dev/null | cut -d' ' -f1)
            local sha256_hash=$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1)

            [ -n "$md5_hash" ] && echo "$md5_hash $file" >> "$hash_file_md5"
            [ -n "$sha1_hash" ] && echo "$sha1_hash $file" >> "$hash_file_sha1"
            [ -n "$sha256_hash" ] && echo "$sha256_hash $file" >> "$hash_file_sha256"
        fi
    done

    log_message "${GREEN}[SUCCESS]${NC} Hashes calculados:"
    [ -f "$hash_file_md5" ] && log_message "  MD5: $(wc -l < "$hash_file_md5") arquivos"
    [ -f "$hash_file_sha1" ] && log_message "  SHA1: $(wc -l < "$hash_file_sha1") arquivos"
    [ -f "$hash_file_sha256" ] && log_message "  SHA256: $(wc -l < "$hash_file_sha256") arquivos"

    echo "$hash_file_sha1"  # Retorna SHA1 como padrão
}

# Função para análise heurística de arquivos suspeitos
perform_heuristic_analysis() {
    local file_path="$1"
    local hash_value="$2"
    local suspicion_score=0

    log_message "${YELLOW}[HEURISTIC]${NC} Analisando: $file_path"

    # Verificar tipo de arquivo
    local file_type=$(file -b "$file_path" 2>/dev/null)

    # Verificar extensão vs tipo real
    local extension="${file_path##*.}"
    local filename=$(basename "$file_path")

    # Heurísticas básicas
    if [[ "$filename" =~ ^[0-9a-f]{8,}$ ]]; then
        ((suspicion_score += 2))
        log_message "  [+2] Nome de arquivo suspeito (somente hex)"
    fi

    # Verificar tamanho do arquivo
    local file_size=$(stat -c%s "$file_path" 2>/dev/null)
    if [ "$file_size" -lt 100 ] || [ "$file_size" -gt 100000000 ]; then
        ((suspicion_score += 1))
        log_message "  [+1] Tamanho suspeito: $file_size bytes"
    fi

    # Verificar metadados com exiftool se disponível
    if command -v exiftool &> /dev/null; then
        local metadata=$(exiftool "$file_path" 2>/dev/null)
        if [[ "$metadata" =~ (GPS|Location|Camera) ]] && [[ "$file_type" =~ (JPEG|PNG) ]]; then
            log_message "  [INFO] Imagem contém metadados GPS/localização"
        fi
    fi

    # Verificar strings suspeitas no arquivo
    if command -v strings &> /dev/null; then
        local suspicious_strings=$(strings "$file_path" 2>/dev/null | grep -iE "(password|hack|exploit|payload|shell|backdoor)" | head -3)
        if [ -n "$suspicious_strings" ]; then
            ((suspicion_score += 3))
            log_message "  [+3] Strings suspeitas encontradas"
        fi
    fi

    log_message "  Score de suspeição: $suspicion_score"

    if [ $suspicion_score -ge 5 ]; then
        log_message "${RED}[HIGH-RISK]${NC} Arquivo de alto risco detectado!"
        return 2
    elif [ $suspicion_score -ge 3 ]; then
        log_message "${YELLOW}[MEDIUM-RISK]${NC} Arquivo de risco médio detectado"
        return 1
    else
        return 0
    fi
}

# Função para análise detalhada de arquivos suspeitos
analyze_suspicious_files() {
    local suspicious_count=0
    local high_risk_count=0

    if [ -f "$SUSPICIOUS_LOG" ]; then
        suspicious_count=$(wc -l < "$SUSPICIOUS_LOG")

        if [ $suspicious_count -gt 0 ]; then
            log_message "${RED}[ALERT]${NC} $suspicious_count arquivos suspeitos encontrados!"

            # Análise adicional dos arquivos suspeitos
            while IFS='|' read -r file_path hash_value timestamp status type_info; do
                log_message "${YELLOW}[ANALYSIS]${NC} Analisando: $file_path"

                # Verificar se o arquivo ainda existe
                if [ ! -f "$file_path" ]; then
                    log_message "  ${RED}[ERROR]${NC} Arquivo não encontrado"
                    continue
                fi

                # Verificar tipo de arquivo
                file_type=$(file -b "$file_path" 2>/dev/null)
                log_message "  Tipo: $file_type"

                # Verificar tamanho
                file_size=$(stat -c%s "$file_path" 2>/dev/null)
                log_message "  Tamanho: $file_size bytes"

                # Verificar extensão vs tipo real
                extension="${file_path##*.}"
                log_message "  Extensão: $extension"
                log_message "  Status: $status"

                # Realizar análise heurística
                perform_heuristic_analysis "$file_path" "$hash_value"
                local heuristic_result=$?

                if [ $heuristic_result -ge 2 ]; then
                    ((high_risk_count++))
                fi

                # Marcar para revisão manual se for imagem/vídeo
                if [[ "$file_type" =~ (image|video|JPEG|PNG|GIF|MP4|AVI|WebM) ]]; then
                    log_message "${RED}[PRIORITY]${NC} Arquivo de mídia requer revisão manual URGENTE"

                    # Tentar extrair metadados básicos
                    if command -v identify &> /dev/null; then
                        local img_info=$(identify "$file_path" 2>/dev/null | head -1)
                        log_message "  Info da imagem: $img_info"
                    fi
                fi

                echo "----------------------------------------" >> "$REPORT_FILE"

            done < "$SUSPICIOUS_LOG"

            log_message "${RED}[SUMMARY]${NC} Arquivos de alto risco: $high_risk_count"
        fi
    fi

    return $suspicious_count
}

# Função para gerar relatório final
generate_final_report() {
    local total_files="$1"
    local suspicious_count="$2"
    local blacklisted_count="${3:-0}"

    cat << EOF >> "$REPORT_FILE"

========================================
RELATÓRIO FINAL DE AUDITORIA
========================================
Data/Hora: $(date)
Total de arquivos analisados: $total_files
Arquivos suspeitos: $suspicious_count
Arquivos blacklisted: $blacklisted_count
Taxa de conformidade: $(( (total_files - suspicious_count - blacklisted_count) * 100 / (total_files > 0 ? total_files : 1) ))%

RECOMENDAÇÕES:
1. Revisar manualmente todos os arquivos listados em: $SUSPICIOUS_LOG
2. Executar análise antivírus nos arquivos suspeitos
3. Verificar logs de acesso dos arquivos suspeitos
4. Considerar isolamento preventivo dos arquivos até análise completa

PRÓXIMOS PASSOS:
- Executar ferramentas especializadas em detecção de conteúdo (PhotoDNA, etc.)
- Análise forense completa se material suspeito for confirmado
- Documentar cadeia de custódia se necessário
========================================
EOF

    log_message "${GREEN}[COMPLETE]${NC} Relatório salvo em: $REPORT_FILE"
}

# Função principal otimizada
main() {
    local target_path="${1:-/home}"
    local use_bulk="${2:-true}"

    log_message "${GREEN}[START]${NC} Iniciando auditoria de integridade"
    log_message "Diretório alvo: $target_path"
    log_message "Modo bulk: $use_bulk"

    # Verificar se o diretório existe
    if [ ! -d "$target_path" ]; then
        log_message "${RED}[ERROR]${NC} Diretório não encontrado: $target_path"
        exit 1
    fi

    setup_environment

    # Testar conectividade com CIRCL
    local circl_available=false
    if test_circl_connectivity; then
        circl_available=true
    fi

    if [ "$circl_available" = false ]; then
        log_message "${YELLOW}[WARNING]${NC} Continuando sem CIRCL API - usando apenas análise local"
    fi

    # Calcular hashes de múltiplos tipos
    local hash_file=$(calculate_file_hashes_multi "$target_path")
    local total_files=$(wc -l < "$hash_file" 2>/dev/null || echo "0")

    log_message "${YELLOW}[INFO]${NC} Total de arquivos para análise: $total_files"

    if [ "$total_files" -eq 0 ]; then
        log_message "${YELLOW}[WARNING]${NC} Nenhum arquivo encontrado para análise"
        generate_final_report 0 0 0
        return 0
    fi

    # Estratégia de verificação
    local suspicious_count=0
    local known_count=0
    local blacklisted_count=0

    if [ "$circl_available" = true ] && [ "$use_bulk" = true ] && [ "$total_files" -gt 100 ]; then
        log_message "${YELLOW}[INFO]${NC} Usando verificação em lote (bulk) para eficiência"

        # Tentar verificação em lote primeiro
        if ! check_bulk_hashes_circl "$hash_file" "sha1"; then
            log_message "${YELLOW}[INFO]${NC} Fallback para verificação individual"
            use_bulk=false
        fi
    else
        use_bulk=false
    fi

    # Verificação individual se bulk não funcionou ou não foi usada
    if [ "$use_bulk" = false ]; then
        log_message "${YELLOW}[INFO]${NC} Iniciando verificação individual de hashes..."

        local processed=0
        while read -r hash_value file_path; do
            ((processed++))

            # Mostrar progresso a cada 100 arquivos
            if [ $((processed % 100)) -eq 0 ]; then
                log_message "${YELLOW}[PROGRESS]${NC} Processados: $processed/$total_files"
            fi

            if [ "$circl_available" = true ]; then
                case $(check_hash_comprehensive "$hash_value" "$file_path") in
                    0) ((known_count++)) ;;
                    1) ((suspicious_count++)) ;;
                    2) ((blacklisted_count++)) ;;
                esac
            else
                # Apenas verificação local se CIRCL não disponível
                if check_hash_blacklist "$hash_value" "$file_path"; then
                    ((blacklisted_count++))
                elif check_hash_local_good "$hash_value" "$file_path"; then
                    ((known_count++))
                else
                    ((suspicious_count++))
                    echo "$file_path|$hash_value|$(date)|NO_API|sha1" >> "$SUSPICIOUS_LOG"
                fi
            fi

            # Rate limiting para não sobrecarregar a API
            [ "$circl_available" = true ] && sleep 0.05

        done < "$hash_file"
    fi

    # Análise detalhada dos suspeitos
    analyze_suspicious_files

    # Estatísticas finais
    log_message "${GREEN}[STATISTICS]${NC}"
    log_message "  Total de arquivos: $total_files"
    log_message "  Conhecidos (limpos): $known_count"
    log_message "  Suspeitos: $suspicious_count"
    log_message "  Blacklisted: $blacklisted_count"

    # Gerar relatório final
    generate_final_report "$total_files" "$suspicious_count" "$blacklisted_count"

    # Cleanup
    rm -f "$BULK_HASH_FILE" "$TEMP_DIR"/file_hashes_*.txt

    if [ $((suspicious_count + blacklisted_count)) -gt 0 ]; then
        log_message "${RED}[ALERT]${NC} AÇÃO NECESSÁRIA: Arquivos problemáticos detectados!"
        exit 1
    else
        log_message "${GREEN}[SUCCESS]${NC} Nenhum arquivo problemático detectado"
        exit 0
    fi
}

# Verificar dependências
check_dependencies() {
    local deps=("curl" "sha1sum" "file" "stat")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo "Erro: $dep não está instalado"
            exit 1
        fi
    done
}

# Exibir uso
show_usage() {
    cat << EOF
USO: $0 [DIRETÓRIO] [bulk|individual]

DESCRIÇÃO:
    Script de verificação de integridade usando CIRCL hashlookup API

PARÂMETROS:
    DIRETÓRIO    - Diretório a ser analisado (padrão: /home)
    bulk         - Usar verificação em lote (padrão para >100 arquivos)
    individual   - Forçar verificação individual

EXEMPLOS:
    $0                          # Analisa /home com modo automático
    $0 /var/www                 # Analisa diretório específico
    $0 /media/usb individual    # Força verificação individual
    $0 /tmp bulk                # Força verificação em lote

ENDPOINTS CIRCL UTILIZADOS:
    - GET  /info                # Informações da API
    - GET  /lookup/md5/{hash}   # Lookup individual MD5
    - GET  /lookup/sha1/{hash}  # Lookup individual SHA1
    - GET  /lookup/sha256/{hash}# Lookup individual SHA256
    - POST /bulk/md5            # Verificação em lote MD5
    - POST /bulk/sha1           # Verificação em lote SHA1

ARQUIVOS GERADOS:
    - $LOG_DIR/audit_report_*.txt       # Relatório detalhado
    - $LOG_DIR/suspicious_files.log     # Lista de arquivos suspeitos
    - $LOG_DIR/known_good_hashes.db     # Cache local de hashes conhecidos
EOF
}

# Verificar argumentos
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

check_dependencies
main "$@"
