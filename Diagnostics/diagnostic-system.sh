#!/bin/bash

# Enhanced Diagnostic System Script - VERSÃO COMPLETA
# diagnostic-system.sh v3.7 - 04.06.2025
# Mantém TODAS as funcionalidades originais + suporte a parâmetros

version="v3.7 - 04.06.2025"

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

# Função para log com timestamp
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

# Solicita senha de administrador (apenas se necessário)
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
    sleep 3
fi

# === FUNÇÃO: TESTE DE ARMAZENAMENTO COMPLETO (Testes 01 e 02) ===
test_storage() {
    echo -e "🔍 Teste 01: Verificando armazenamento..."

    # Verifica fstab vs montagens atuais
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
    sleep 3

    # Verifica sistemas de arquivos com erros
    log_message "Verificando integridade dos sistemas de arquivos..."
    fs_errors=$(dmesg | grep -i "ext[234]\|xfs\|btrfs" | grep -i "error\|corrupt\|remount.*read-only" | tail -10)
    if [ -n "$fs_errors" ]; then
        echo -e "❌ ERRO: Detectados erros no sistema de arquivos!"
        echo "$fs_errors"
        add_error
    else
        echo -e "✅ OK: Nenhum erro de sistema de arquivos detectado"
    fi

    echo ""
    sleep 3

    # Verifica dispositivos com bad blocks
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
    echo -e "OBSERVAÇÃO: Este assistente não consegue verificar SMART de discos em RAID por Hardware."

    echo ""
    sleep 3

    # === TESTE 02 - Verificando utilização de armazenamento ===
    echo -e "🔍 Teste 02: Verificando utilização de armazenamento..."

    # Verifica 100% de uso
    diskfull=$(df -h | awk '$5 == "100%" {print $0}')
    if [ -z "$diskfull" ]; then
        echo -e "✅ OK: Nenhum disco com 100% de uso"
    else
        echo -e "❌ CRÍTICO: Armazenamento(s) lotado(s)!"
        echo "$diskfull"
        add_error
    fi

    echo ""
    sleep 3

    # Verifica uso acima de 90%
    log_message "Verificando uso acima de 90%..."
    disk_high=$(df -h | awk 'NR>1 && $5 != "-" {gsub(/%/, "", $5); if ($5 > 90) print $0}')
    if [ -n "$disk_high" ]; then
        echo -e "⚠️  AVISO: Armazenamento(s) com mais de 90% de uso:"
        echo "$disk_high"
        add_warning
    else
        echo -e "✅ OK: Nenhum disco com +90% de uso"
    fi

    echo ""
    sleep 3

    # Verifica inodes
    log_message "Verificando utilização de inodes..."
    inode_full=$(df -i | awk 'NR>1 && $5 != "-" {gsub(/%/, "", $5); if ($5 > 95) print $0}')
    if [ -n "$inode_full" ]; then
        echo -e "❌ ERRO: Sistema(s) de arquivo(s) com inodes esgotados!"
        echo "$inode_full"
        add_error
    else
        echo -e "✅ OK: Nenhum disco com inodes esgotados"
    fi
    echo ""
    sleep 3
}

# === FUNÇÃO: TESTE DE REDE COMPLETO (Teste 03) ===
test_network() {
    echo -e "🔍 Teste 03: Verificando conectividade de rede e possíveis problemas de rotas..."

    # TESTE COMPLETO DE DNS - TODOS OS 8 SERVIDORES
    dns_servers=("1.1.1.1" "1.0.0.1" "8.8.8.8" "8.8.4.4" "208.67.222.222" "208.67.220.220" "200.225.197.34" "200.225.197.37")
    dns_name=("Cloudflare 1" "Cloudflare 2" "Google 1" "Google 2" "OpenDNS 1" "OpenDNS 2" "Algar 1" "Algar 2")
    dns_working=0

    echo "Testando servidores DNS..."
    echo "=========================="

    for i in "${!dns_servers[@]}"; do
        dns="${dns_servers[$i]}"
        name="${dns_name[$i]}"
        
        echo -n "Testando $name ($dns)... "
        
        ping_output=$(ping -c 1 -W 2 "$dns" 2>&1)
        ping_status=$?
        
        if [ $ping_status -eq 0 ]; then
            echo "✅ Respondendo!"
            echo "$ping_output" | grep "time=" | head -1
            ((dns_working++))
        else
            echo "❌ Não acessível!"
            echo "Erro: $ping_output"
        fi
        echo ""
    done

    echo "=========================="
    echo "Resumo: $dns_working de ${#dns_servers[@]} servidores DNS estão funcionando."

    echo ""
    sleep 3

    # Verifica interfaces de rede
    log_message "Verificando interfaces de rede..."
    network_down=$(ip -o link show | awk '/state DOWN/ {print $2,$17}')
    if [ -n "$network_down" ]; then
        echo -e "⚠️  AVISO: Interface(s) de rede inativa(s) detectadas (ignore as interfaces BR-xxxxx, VIRBR0 e/ou DOCKER0):"
        echo "$network_down"
        add_warning
    else
        echo -e "✅ Todas as interfaces de rede existentes estão ativas!"
    fi

    echo ""
    sleep 3

    # Verifica resolução DNS
    log_message "Verificando resolução DNS..."
    if ! nslookup google.com >/dev/null 2>&1; then
        echo -e "⚠️  AVISO: Problemas na resolução DNS"
        add_warning
    else
        echo -e "✅ Resolução DNS OK, os seguintes dados foram coletados: "
        meuipwan=$(dig @resolver4.opendns.com myip.opendns.com +short)
        meugateway=$(ip route get 1.1.1.1 | grep -oP 'via \K\S+')
        meudevice=$(ip route get 1.1.1.1 | grep -oP 'dev \K\S+')
        meuiplan=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')
        minhasubnet="${meugateway%.*}.0"
        echo -e "IP WAN   : $meuipwan \nIP LAN   : $meuiplan \nGateway  : $meugateway \nSubnet   : $minhasubnet \nInterface: $meudevice"
    fi

    echo ""
    sleep 3
}

# === FUNÇÃO: TESTE DE SERVIÇOS COMPLETO (Teste 04) ===
test_services() {
    echo -e "🔍 Teste 04: Verificando serviços essenciais..."

    # Lista de serviços críticos para verificar
    critical_services=("ssh.socket" "systemd-resolved" "NetworkManager" "cron")

    # Verifica serviços do sistema
    for service in "${critical_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "✅ OK: Serviço $service está ativo"
        else
            if systemctl list-unit-files --type=service | grep -q "^$service"; then
                echo -e "⚠️  AVISO: Serviço $service está inativo, isso está correto?"
                add_warning
            fi
        fi
    done

    # Testando Docker (melhorado)
    log_message "Verificando Docker..."
    if systemctl is-active --quiet docker 2>/dev/null; then
        echo -e "✅ OK: Docker está ativo"
    elif command -v docker >/dev/null 2>&1; then
        echo -e "❌ ERRO: Docker está instalado mas não está executando! Isso está correto?"
        add_error
    else
        echo -e "✅ OK: Docker não está instalado, mas isto está correto?"
    fi
    
    # Verifica containers problemáticos (se Docker estiver ativo)
    if systemctl is-active --quiet docker 2>/dev/null; then
        exited_containers=$(sudo docker ps -f status=exited -q 2>/dev/null)
        if [ -n "$exited_containers" ]; then
            exited_count=$(echo "$exited_containers" | wc -l)
            echo -e "⚠️  AVISO: $exited_count container(s) em estado de EXITED, isto está correto?"
            sudo docker ps -f status=exited --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
            add_warning
        else
            echo -e "✅ OK: Containers ativos e operando normalmente de acordo com o sistema."
        fi
        
        restarting_containers=$(sudo docker ps -f status=restarting -q 2>/dev/null)
        if [ -n "$restarting_containers" ]; then
            echo -e "❌ ERRO: Container(s) em estado de restart infinito!"
            sudo docker ps -f status=restarting --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
            add_error
        else
            echo -e "✅ OK: Não há containers reiniciando em estado de erro."
        fi
        
        # Reproduzindo o erro de permissão do log original
        docker_perm_test=$(sudo docker ps 2>&1)
        if echo "$docker_perm_test" | grep -q "permission denied"; then
            echo "permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock: Get \"http://%2Fvar%2Frun%2Fdocker.sock/v1.47/containers/json\": dial unix /var/run/docker.sock: connect: permission denied"
        fi
        
        # Verifica containers com uso alto de recursos
        high_cpu_containers=$(sudo docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}" 2>/dev/null | awk 'NR>1 {gsub(/%/, "", $2); if ($2 > 80) print $0}')
        if [ -n "$high_cpu_containers" ]; then
            echo -e "⚠️  AVISO: Container(s) com alto uso de CPU:"
            echo "$high_cpu_containers"
            add_warning
        else
            echo -e "✅ OK: Não há containers com alto consumo de CPU."
        fi
    fi

    # Testando LibVirt (melhorado)
    log_message "Verificando LibVirt..."
    if systemctl is-active --quiet libvirtd 2>/dev/null; then
        echo -e "✅ OK: LibVirt está ativo e operando."
        
        # Verifica VMs com problemas
        if command -v virsh >/dev/null 2>&1; then
            vm_problems=$(sudo virsh list --all | grep -E "shut off|crashed|paused")
            if [ -n "$vm_problems" ]; then
                echo -e "⚠️  AVISO: VMs em algum estado de pausa, travado ou desligado:"
                echo "$vm_problems"
                add_warning
            else
                echo -e "✅ OK: As VMs existentes estão executando."
            fi
        fi
    elif command -v libvirtd >/dev/null 2>&1; then
        echo -e "⚠️  AVISO: LibVirt está instalado mas não está executando!"
        add_warning
    else
        echo -e "✅ OK: LibVirt não está instalado neste servidor. Sem capacidades de virtualização."
    fi
    echo ""
    sleep 3
}

# === FUNÇÃO: TESTE DE SISTEMA COMPLETO (Teste 05) ===
test_system() {
    echo -e "🔍 Teste 05: Verificações adicionais do sistema..."

    # Verifica carga do sistema
    load_avg=$(uptime | awk '{print $(NF-2)}' | sed 's/,//')
    cpu_cores=$(nproc)
    if (( $(echo "$load_avg > $cpu_cores * 2" | bc -l 2>/dev/null || echo "0") )); then
        echo -e "⚠️  AVISO: Carga do sistema alta ($load_avg com $cpu_cores cores)"
        add_warning
    else
        echo -e "✅ OK: Carga do sistema normal ($load_avg)"
    fi

    # Verifica memória
    mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [ "$mem_usage" -gt 90 ]; then
        echo -e "❌ ERRO: Uso de memória alto crítico (${mem_usage}%)"
        add_error
    elif [ "$mem_usage" -gt 80 ]; then
        echo -e "⚠️  AVISO: Uso de memória alto (${mem_usage}%)"
        add_warning
    else
        echo -e "✅ OK: Uso de memória normal (${mem_usage}%)"
    fi

    # Verifica processos zumbis
    zombies=$(ps aux | awk '$8 ~ /^Z/ { count++ } END { print count+0 }')
    if [ "$zombies" -gt 0 ]; then
        echo -e "⚠️  AVISO: $zombies processo(s) zumbi detectado(s)"
        add_warning
    else
        echo -e "✅ OK: Nenhum processo zumbi detectado."
    fi

    # Verifica logs de erro recentes
    log_message "Verificando logs de sistema..."
    recent_errors=$(sudo journalctl --since "1 hour ago" -p err -q --no-pager | wc -l)
    if [ "$recent_errors" -gt 10 ]; then
        echo -e "⚠️  AVISO: $recent_errors erros no log da última hora"
        add_warning
    fi

    echo ""
}

# === FUNÇÃO: INFORMAÇÕES COMPLETAS DO SISTEMA ===
show_system_info() {
    echo '📊 INFORMAÇÕES DO SISTEMA'
    echo '========================='
    echo ''
    echo '🖥️  Sistema Operacional:'
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        echo "   Distro: $PRETTY_NAME"
        echo "   Versão: $VERSION"
    else
        echo '   Informações não disponíveis'
    fi
    echo ''
    
    echo '💻 Hardware:'
    echo "   CPU: $(nproc) núcleo(s)"
    echo "   Modelo: $(cat /proc/cpuinfo | grep 'model name' | head -1 | cut -d: -f2 | sed 's/^ *//')"
    echo "   Memória Total: $(free -h | awk 'NR==2{print $2}')"
    echo "   Memória Usada: $(free -h | awk 'NR==2{print $3}')"
    echo "   Memória Livre: $(free -h | awk 'NR==2{print $4}')"
    echo ''
    
    echo '💾 Armazenamento:'
    df -h | grep -E '^/dev/' | while read line; do
        echo "   $line"
    done
    echo ''
    
    echo '🔗 Rede:'
    ip -o link show | grep -E 'state UP' | while read line; do
        interface=$(echo $line | awk '{print $2}' | sed 's/://')
        state=$(echo $line | awk '{print $9}')
        echo "   Interface $interface: $state"
    done
    echo ''
    
    echo 'Sistema:'
    echo "   Uptime: $(uptime -p)"
    echo "   Data/Hora: $(date)"
    echo "   Carga: $(uptime | awk '{print $(NF-2), $(NF-1), $NF}')"
    echo ''
    
    echo '🔧 Serviços Principais:'
    services=('ssh' 'cron' 'systemd-resolved' 'NetworkManager')
    for service in "${services[@]}"; do
        if systemctl is-active --quiet $service 2>/dev/null; then
            echo "   $service: Ativo"
        else
            echo "   $service: Inativo"
        fi
    done
}

# === FUNÇÃO: INFORMAÇÕES RÁPIDAS ===
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
        # Teste completo (padrão) - EXECUTA TODOS OS TESTES SEQUENCIALMENTE
        test_storage
        test_network
        test_services
        test_system
        ;;
esac

# === RESUMO FINAL (apenas para teste completo ou modo terminal) ===
if [ -z "$TEST_TYPE" ] || [ "$IS_CGI" = "false" ]; then
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
        if [ "$IS_CGI" = "false" ]; then
            echo ""
            sleep 5
        fi
        exit 0
    elif [ $ERRORS -eq 0 ]; then
        echo -e "⚠️  SISTEMA COM AVISOS: Verificar itens mencionados"
        if [ "$IS_CGI" = "false" ]; then
            echo ""
            sleep 5
        fi
        exit 1
    else
        echo -e "🚨 SISTEMA COM PROBLEMAS CRÍTICOS: Ação imediata necessária!"
        if [ "$IS_CGI" = "false" ]; then
            echo ""
            sleep 5
        fi
        exit 2
    fi
fi
