#!/bin/bash

# Enhanced Diagnostic System Script
# diagnostic-system.sh v4.0
# Suporta parâmetros para evitar duplicação

version="v4.0 - 04.06.2025"

# Verificar se está sendo executado via CGI
if [ -n "$REQUEST_METHOD" ]; then
    IS_CGI=true
    SKIP_AUTH=true
else
    IS_CGI=false
    SKIP_AUTH=false
fi

# Processar parâmetros da linha de comando
while [[ $# -gt 0 ]]; do
    case $1 in
        --test=*)
            TEST_TYPE="${1#*=}"
            shift
            ;;
        --info)
            MODE="info"
            shift
            ;;
        --quick)
            MODE="quick"
            shift
            ;;
        --no-auth)
            SKIP_AUTH=true
            shift
            ;;
        *)
            echo "Parâmetro desconhecido: $1"
            exit 1
            ;;
    esac
done

# Contadores de problemas
WARNINGS=0
ERRORS=0

# Função para log
log_message() {
    echo "   $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Função para incrementar contadores
add_warning() { ((WARNINGS++)); }
add_error() { ((ERRORS++)); }

# Cabeçalho (apenas se não for CGI)
if [ "$IS_CGI" = "false" ]; then
    echo "============================================"
    echo "Diagnóstico do Sistema $version"
    echo "============================================"
    echo ""
fi

# Autenticação (apenas se necessário)
if [ "$SKIP_AUTH" = "false" ]; then
    echo "Digite sua senha de administrador:"
    echo ""
    if sudo -v; then
        echo -e "✅ Autenticação realizada com sucesso!"
    else
        echo -e "❌ Falha na autenticação!"
        exit 1
    fi
    echo ""
fi

# === FUNÇÕES DE TESTE INDIVIDUAIS ===

test_storage() {
    echo -e "🔍 Teste 01: Verificando armazenamento..."
    
    log_message "Verificando consistência do /etc/fstab..."
    diskmount_output=$(sudo mount -a 2>&1)
    diskmount_status=$?
    
    if [ $diskmount_status -eq 0 ]; then
        echo -e "✅ OK: Todos os sistemas de arquivos do fstab estão montados"
    else
        echo -e "❌ ERRO: Problemas na montagem de sistemas de arquivos!"
        echo "Detalhes: $diskmount_output"
        add_error
    fi
    
    echo ""
    
    log_message "Verificando integridade dos sistemas de arquivos..."
    fs_errors=$(sudo dmesg 2>/dev/null | grep -i "ext[234]\|xfs\|btrfs" | grep -i "error\|corrupt\|remount.*read-only" | tail -10)
    if [ -n "$fs_errors" ]; then
        echo -e "❌ ERRO: Detectados erros no sistema de arquivos!"
        echo "$fs_errors"
        add_error
    else
        echo -e "✅ OK: Nenhum erro de sistema de arquivos detectado"
    fi
    
    echo ""
    
    log_message "Verificando armazenamento com possíveis BAD BLOCKS..."
    smart_devices=$(lsblk -d -o NAME,TYPE | grep disk | awk '{print $1}')
    for device in $smart_devices; do
        if command -v smartctl >/dev/null 2>&1; then
            smart_status=$(sudo smartctl -H /dev/"$device" 2>/dev/null | grep "SMART overall-health")
            if echo "$smart_status" | grep -q "FAILED"; then
                echo -e "❌ CRÍTICO: Dispositivo /dev/$device com falha SMART!"
                add_error
            else
                echo -e "✅ OK: Dispositivo /dev/$device sem problemas SMART para relatar."
            fi
        fi
    done
    
    echo ""
    
    echo -e "🔍 Teste 02: Verificando utilização de armazenamento..."
    
    diskfull=$(df -h | awk '$5 == "100%" {print $0}')
    if [ -z "$diskfull" ]; then
        echo -e "✅ OK: Nenhum disco com 100% de uso"
    else
        echo -e "❌ CRÍTICO: Armazenamento(s) lotado(s)!"
        echo "$diskfull"
        add_error
    fi
    
    echo ""
}

test_network() {
    echo -e "🔍 Teste 03: Verificando conectividade de rede..."
    
    dns_servers=("1.1.1.1" "1.0.0.1" "8.8.8.8" "8.8.4.4")
    dns_name=("Cloudflare 1" "Cloudflare 2" "Google 1" "Google 2")
    dns_working=0
    
    echo "Testando servidores DNS..."
    echo "=========================="
    
    for i in "${!dns_servers[@]}"; do
        dns="${dns_servers[$i]}"
        name="${dns_name[$i]}"
        
        echo -n "Testando $name ($dns)... "
        
        if ping -c 1 -W 2 "$dns" >/dev/null 2>&1; then
            echo "✅ Respondendo!"
            ((dns_working++))
        else
            echo "❌ Não acessível!"
        fi
    done
    
    echo "=========================="
    echo "Resumo: $dns_working de ${#dns_servers[@]} servidores DNS estão funcionando."
    
    echo ""
    
    log_message "Verificando interfaces de rede..."
    network_down=$(ip -o link show | awk '/state DOWN/ && !/virbr/ && !/br-/ && !/docker/ && !/lo/ {print $2,$17}')
    if [ -n "$network_down" ]; then
        echo -e "⚠️  AVISO: Interface(s) de rede física(s) inativa(s):"
        echo "$network_down"
        add_warning
    else
        echo -e "✅ OK: Todas as interfaces de rede físicas estão ativas!"
    fi
    
    echo ""
}

test_services() {
    echo -e "🔍 Teste 04: Verificando serviços essenciais..."
    
    critical_services=("ssh.socket" "systemd-resolved" "NetworkManager" "cron")
    
    for service in "${critical_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "✅ OK: Serviço $service está ativo"
        else
            if systemctl list-unit-files --type=service | grep -q "^$service"; then
                echo -e "⚠️  AVISO: Serviço $service está inativo"
                add_warning
            fi
        fi
    done
    
    log_message "Verificando Docker..."
    if systemctl is-active --quiet docker 2>/dev/null; then
        echo -e "✅ OK: Docker está ativo"
        
        if sudo docker ps >/dev/null 2>&1; then
            echo -e "✅ OK: Docker respondendo normalmente"
        else
            echo -e "⚠️  AVISO: Docker sem permissões adequadas"
            add_warning
        fi
    elif command -v docker >/dev/null 2>&1; then
        echo -e "❌ ERRO: Docker instalado mas não executando!"
        add_error
    else
        echo -e "✅ OK: Docker não instalado"
    fi
    
    echo ""
}

test_system() {
    echo -e "🔍 Teste 05: Verificações adicionais do sistema..."
    
    # Carga do sistema
    load_avg=$(uptime | awk '{print $(NF-2)}' | sed 's/,//')
    cpu_cores=$(nproc)
    if (( $(echo "$load_avg > $cpu_cores * 2" | bc -l 2>/dev/null || echo "0") )); then
        echo -e "⚠️  AVISO: Carga do sistema alta ($load_avg com $cpu_cores cores)"
        add_warning
    else
        echo -e "✅ OK: Carga do sistema normal ($load_avg)"
    fi
    
    # Memória
    mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [ "$mem_usage" -gt 90 ]; then
        echo -e "❌ ERRO: Uso de memória crítico (${mem_usage}%)"
        add_error
    elif [ "$mem_usage" -gt 80 ]; then
        echo -e "⚠️  AVISO: Uso de memória alto (${mem_usage}%)"
        add_warning
    else
        echo -e "✅ OK: Uso de memória normal (${mem_usage}%)"
    fi
    
    # Processos zumbi
    zombies=$(ps aux | awk '$8 ~ /^Z/ { count++ } END { print count+0 }')
    if [ "$zombies" -gt 0 ]; then
        echo -e "⚠️  AVISO: $zombies processo(s) zumbi detectado(s)"
        add_warning
    else
        echo -e "✅ OK: Nenhum processo zumbi detectado"
    fi
    
    echo ""
}

show_system_info() {
    echo '📊 INFORMAÇÕES DO SISTEMA'
    echo '========================='
    echo ''
    echo '🖥️  Sistema Operacional:'
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        echo "   Distro: $PRETTY_NAME"
        echo "   Versão: $VERSION"
    fi
    echo ''
    echo '💻 Hardware:'
    echo "   CPU: $(nproc) núcleo(s)"
    echo "   Memória Total: $(free -h | awk 'NR==2{print $2}')"
    echo "   Memória Usada: $(free -h | awk 'NR==2{print $3}')"
    echo ''
    echo '📊 Status:'
    echo "   Uptime: $(uptime -p)"
    echo "   Carga: $(uptime | awk '{print $(NF-2)}' | sed 's/,//')"
    echo "   Data/Hora: $(date)"
}

show_quick_info() {
    echo "Hostname: $(hostname)"
    echo "Uptime: $(uptime -p)"
    echo "Load: $(uptime | awk '{print $(NF-2)}' | sed 's/,//')"
    echo "Memory: $(free | awk 'NR==2{printf "%.0f%%", $3*100/$2}')"
    echo "Disk: $(df / | awk 'NR==2{print $5}')"
}

# === EXECUÇÃO BASEADA NO MODO ===

case "$MODE" in
    "info")
        show_system_info
        exit 0
        ;;
    "quick")
        show_quick_info
        exit 0
        ;;
esac

# Execução baseada no tipo de teste
case "$TEST_TYPE" in
    "storage")
        test_storage
        ;;
    "network")
        test_network
        ;;
    "services")
        test_services
        ;;
    "system")
        test_system
        ;;
    *)
        # Teste completo (padrão)
        test_storage
        sleep 1
        test_network
        sleep 1
        test_services
        sleep 1
        test_system
        ;;
esac

# Resumo final (apenas para teste completo)
if [ -z "$TEST_TYPE" ]; then
    echo ""
    echo "============================================"
    echo -e "📊 RESUMO DO DIAGNÓSTICO"
    echo "============================================"
    log_message "Diagnóstico concluído"
    echo -e "Erros críticos encontrados: $ERRORS"
    echo -e "Avisos encontrados: $WARNINGS"
    echo ""
    
    if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
        echo -e "🎉 SISTEMA SAUDÁVEL: Nenhum problema detectado!"
        exit 0
    elif [ $ERRORS -eq 0 ]; then
        echo -e "⚠️  SISTEMA COM AVISOS: Verificar itens mencionados"
        exit 1
    else
        echo -e "🚨 SISTEMA COM PROBLEMAS CRÍTICOS: Ação imediata necessária!"
        exit 2
    fi
fi
