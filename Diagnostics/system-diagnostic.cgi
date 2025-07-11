#!/bin/bash

# CGI Script COMPLETO para Sistema de Diagnostico
# system-diagnostic.cgi v3.7 - 04.06.2025
# ZERO redundância - delega 100% para o script principal

# Cabeçalhos CGI
echo "Content-Type: text/plain"
echo "Cache-Control: no-cache"
echo ""

# Diretório onde está o script de diagnóstico
DIAGNOSTIC_SCRIPT="/usr/local/bin/diagnostic-system.sh"

# Função para log de debug (opcional)
log_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $1" >&2
}

# Função para retornar erro JSON
return_error() {
    echo "{\"status\":\"error\",\"message\":\"$1\"}"
    exit 1
}

# Função para retornar sucesso
return_success() {
    echo "$1"
    exit 0
}

# Verificar se o script de diagnóstico existe
if [ ! -f "$DIAGNOSTIC_SCRIPT" ]; then
    return_error "Script de diagnóstico não encontrado em $DIAGNOSTIC_SCRIPT"
fi

# Verificar se o script é executável
if [ ! -x "$DIAGNOSTIC_SCRIPT" ]; then
    return_error "Script de diagnóstico não é executável"
fi

# Ler dados POST
if [ "$REQUEST_METHOD" = "POST" ]; then
    read -r POST_DATA
else
    return_error "Método não suportado. Use POST."
fi

# Decodificar URL
decode_url() {
    echo -e "$(echo "$1" | sed 's/+/ /g; s/%\([0-9a-fA-F][0-9a-fA-F]\)/\\x\1/g')"
}

# Parsear parâmetros POST
parse_params() {
    local data="$1"
    IFS='&' read -ra PARAMS <<< "$data"
    
    declare -A PARSED
    for param in "${PARAMS[@]}"; do
        IFS='=' read -ra KV <<< "$param"
        if [ ${#KV[@]} -eq 2 ]; then
            key=$(decode_url "${KV[0]}")
            value=$(decode_url "${KV[1]}")
            PARSED["$key"]="$value"
        fi
    done
    
    # Exportar como variáveis globais
    ACTION="${PARSED[action]}"
    TEST_TYPE="${PARSED[test]}"
}

# Parsear dados recebidos
parse_params "$POST_DATA"

log_debug "Ação recebida: $ACTION"
log_debug "Tipo de teste: $TEST_TYPE"

# Executar ação baseada no parâmetro
case "$ACTION" in
    "full-diagnostic")
        log_debug "Executando diagnóstico completo"
        
        # Executar o script completo com --no-auth para pular autenticação
        if output=$(timeout 300 "$DIAGNOSTIC_SCRIPT" --no-auth 2>&1); then
            return_success "$output"
        else
            return_error "Erro ao executar diagnóstico completo: $output"
        fi
        ;;
        
    "specific-test")
        log_debug "Executando teste específico: $TEST_TYPE"
        
        case "$TEST_TYPE" in
            "storage")
                # Delegar para o script principal com parâmetro --test=storage
                output=$(timeout 300 "$DIAGNOSTIC_SCRIPT" --no-auth 2>&1)
                exit_code=$?
                if [ $exit_code -le 2 ]; then
                    return_success "$output"
                else
                    return_error "Erro ao executar teste de armazenamento: $output"
                fi
                ;;
                
            "network")
                # Delegar para o script principal com parâmetro --test=network
                if output=$(timeout 180 "$DIAGNOSTIC_SCRIPT" --test=network --no-auth 2>&1); then
                    return_success "$output"
                else
                    return_error "Erro ao executar teste de rede: $output"
                fi
                ;;
                
            "services")
                # Delegar para o script principal com parâmetro --test=services
                if output=$(timeout 120 "$DIAGNOSTIC_SCRIPT" --test=services --no-auth 2>&1); then
                    return_success "$output"
                else
                    return_error "Erro ao executar teste de serviços: $output"
                fi
                ;;
                
            "system")
                # Delegar para o script principal com parâmetro --test=system
                if output=$(timeout 60 "$DIAGNOSTIC_SCRIPT" --test=system --no-auth 2>&1); then
                    return_success "$output"
                else
                    return_error "Erro ao executar teste de sistema: $output"
                fi
                ;;
                
            *)
                return_error "Tipo de teste não reconhecido: $TEST_TYPE"
                ;;
        esac
        ;;
        
    "system-info")
        log_debug "Coletando informações do sistema"
        
        # Delegar para o script principal com parâmetro --info
        if output=$(timeout 30 "$DIAGNOSTIC_SCRIPT" --info --no-auth 2>&1); then
            return_success "$output"
        else
            return_error "Erro ao coletar informações do sistema: $output"
        fi
        ;;
        
    "quick-info")
        log_debug "Coletando informações rápidas"
        
        # Delegar para o script principal com parâmetro --quick
        if output=$(timeout 10 "$DIAGNOSTIC_SCRIPT" --quick --no-auth 2>&1); then
            return_success "$output"
        else
            return_error "Erro ao coletar informações rápidas: $output"
        fi
        ;;
        
    "ping")
        log_debug "Ping recebido"
        return_success "pong"
        ;;
        
    *)
        return_error "Ação não reconhecida: $ACTION"
        ;;
esac

# Se chegou até aqui, algo deu errado
return_error "Erro interno do script"
