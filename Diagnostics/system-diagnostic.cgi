#!/bin/bash

# CGI Script Limpo - Apenas Proxy
# system-diagnostic.cgi v2.0
# ZERO redundância - delega tudo para o script principal

# Cabeçalhos CGI
echo "Content-Type: text/plain"
echo "Cache-Control: no-cache"
echo ""

# Script principal
DIAGNOSTIC_SCRIPT="/usr/local/bin/diagnostic-system.sh"

# Função para retornar erro
return_error() {
    echo "{\"status\":\"error\",\"message\":\"$1\"}"
    exit 1
}

# Verificar se o script existe
if [ ! -f "$DIAGNOSTIC_SCRIPT" ] || [ ! -x "$DIAGNOSTIC_SCRIPT" ]; then
    return_error "Script de diagnóstico não encontrado ou não executável"
fi

# Ler dados POST
if [ "$REQUEST_METHOD" = "POST" ]; then
    read -r POST_DATA
else
    return_error "Método não suportado. Use POST."
fi

# Parsear parâmetros
ACTION=$(echo "$POST_DATA" | grep -o 'action=[^&]*' | cut -d= -f2 | sed 's/%20/ /g')
TEST_TYPE=$(echo "$POST_DATA" | grep -o 'test=[^&]*' | cut -d= -f2)

# Processar ações
case "$ACTION" in
    "full-diagnostic")
        # Delegar 100% para o script principal
        timeout 300 "$DIAGNOSTIC_SCRIPT" 2>&1
        ;;
        
    "specific-test")
        # Delegar para o script principal com parâmetro
        timeout 180 "$DIAGNOSTIC_SCRIPT" --test="$TEST_TYPE" 2>&1
        ;;
        
    "system-info")
        # Delegar para o script principal
        timeout 30 "$DIAGNOSTIC_SCRIPT" --info 2>&1
        ;;
        
    "quick-info")
        # Delegar para o script principal
        timeout 10 "$DIAGNOSTIC_SCRIPT" --quick 2>&1
        ;;
        
    "ping")
        echo "pong"
        ;;
        
    *)
        return_error "Ação não reconhecida: $ACTION"
        ;;
esac
