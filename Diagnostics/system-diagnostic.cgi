#!/bin/bash

# CGI Script CORRIGIDO para Sistema de Diagnostico
# Previne processos apache2ctl zumbis

# Cabeçalhos CGI
echo "Content-Type: text/plain"
echo "Cache-Control: no-cache"
echo ""

# === CORREÇÃO PRINCIPAL: AGUARDAR TODOS OS PROCESSOS FILHOS ===

# Configurar tratamento de sinais para evitar zumbis
cleanup_and_exit() {
    local exit_code=${1:-0}
    
    # Aguardar TODOS os processos filhos antes de sair
    wait 2>/dev/null
    
    # Matar processos órfãos se existirem
    jobs -p | xargs -r kill -TERM 2>/dev/null
    sleep 1
    jobs -p | xargs -r kill -KILL 2>/dev/null
    
    exit $exit_code
}

# Instalar handler de cleanup
trap 'cleanup_and_exit 1' EXIT INT TERM

# Diretório onde está o script de diagnóstico
DIAGNOSTIC_SCRIPT="/usr/local/bin/diagnostic-system.sh"

# Função para log de debug (opcional)
log_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $1" >&2
}

# Função para retornar erro JSON
return_error() {
    echo "{\"status\":\"error\",\"message\":\"$1\"}"
    cleanup_and_exit 1
}

# Função para retornar sucesso
return_success() {
    echo "$1"
    cleanup_and_exit 0
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

# === FUNÇÃO CORRIGIDA PARA EXECUTAR COMANDOS SEM ZUMBIS ===
execute_diagnostic_safe() {
    local cmd_args="$1"
    local timeout_val="${2:-300}"
    local output
    
    log_debug "Executando: $DIAGNOSTIC_SCRIPT $cmd_args"
    
    # Executar em background com PID tracking
    {
        timeout "$timeout_val" "$DIAGNOSTIC_SCRIPT" $cmd_args 2>&1
        echo "EXIT_CODE:$?" >&2
    } &
    
    local bg_pid=$!
    
    # Aguardar o processo completar
    wait $bg_pid 2>/dev/null
    local wait_status=$?
    
    # Verificar se ainda existe
    if kill -0 $bg_pid 2>/dev/null; then
        # Processo ainda existe, forçar término
        kill -TERM $bg_pid 2>/dev/null
        sleep 2
        kill -KILL $bg_pid 2>/dev/null
        wait $bg_pid 2>/dev/null
    fi
    
    return $wait_status
}

# Parsear dados recebidos
parse_params "$POST_DATA"

log_debug "Ação recebida: $ACTION"
log_debug "Tipo de teste: $TEST_TYPE"

# Executar ação baseada no parâmetro
case "$ACTION" in
    "full-diagnostic")
        log_debug "Executando diagnóstico completo"
        
        # Executar o script completo com função segura
        if output=$(execute_diagnostic_safe "--no-auth" 300); then
            return_success "$output"
        else
            return_error "Timeout ou falha crítica na execução"
        fi
        ;;
        
    "specific-test")
        log_debug "Executando teste específico: $TEST_TYPE"
        
        case "$TEST_TYPE" in
            "storage")
                if output=$(execute_diagnostic_safe "--test=storage --no-auth" 300); then
                    return_success "$output"
                else
                    return_error "Erro ao executar teste de armazenamento"
                fi
                ;;
                
            "network")
                if output=$(execute_diagnostic_safe "--test=network --no-auth" 180); then
                    return_success "$output"
                else
                    return_error "Erro ao executar teste de rede"
                fi
                ;;
                
            "services")
                if output=$(execute_diagnostic_safe "--test=services --no-auth" 120); then
                    return_success "$output"
                else
                    return_error "Erro ao executar teste de serviços"
                fi
                ;;
                
            "system")
                if output=$(execute_diagnostic_safe "--test=system --no-auth" 60); then
                    return_success "$output"
                else
                    return_error "Erro ao executar teste de sistema"
                fi
                ;;

            "logs")
                if output=$(execute_diagnostic_safe "--test=logs --no-auth" 60); then
                    return_success "$output"
                else
                    return_error "Erro ao executar análise de logs"
                fi
                ;;
                
            *)
                return_error "Tipo de teste não reconhecido: $TEST_TYPE"
                ;;
        esac
        ;;
        
    "status")
        log_debug "Verificando status de execução"
        if find /tmp -name "diagnostic_*.lock" -mmin -10 2>/dev/null | grep -q .; then
            echo "running"
        else
            echo "idle"
        fi
        cleanup_and_exit 0
        ;;
        
    "system-info")
        log_debug "Coletando informações do sistema"
        
        if output=$(execute_diagnostic_safe "--info --no-auth" 30); then
            return_success "$output"
        else
            return_error "Erro ao coletar informações do sistema"
        fi
        ;;
        
    "quick-info")
        log_debug "Coletando informações rápidas"
        
        if output=$(execute_diagnostic_safe "--quick --no-auth" 10); then
            return_success "$output"
        else
            return_error "Erro ao coletar informações rápidas"
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
