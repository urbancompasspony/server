#!/bin/bash

# CGI Script para Sistema de Diagnostico
# system-diagnostic.cgi
# Versao: 1.0

# Cabeçalhos CGI
echo "Content-Type: text/plain"
echo "Cache-Control: no-cache"
echo ""

# Diretorio onde esta o script de diagnostico
DIAGNOSTIC_SCRIPT="/usr/local/bin/diagnostic-system.sh"

# Funçao para log de debug (opcional)
log_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $1" >&2
}

# Funçao para retornar erro JSON
return_error() {
    echo "{\"status\":\"error\",\"message\":\"$1\"}"
    exit 1
}

# Funçao para retornar sucesso
return_success() {
    echo "$1"
    exit 0
}

# Verificar se o script de diagnostico existe
if [ ! -f "$DIAGNOSTIC_SCRIPT" ]; then
    return_error "Script de diagnostico nao encontrado em $DIAGNOSTIC_SCRIPT"
fi

# Verificar se o script e executavel
if [ ! -x "$DIAGNOSTIC_SCRIPT" ]; then
    return_error "Script de diagnostico nao e executavel"
fi

# Ler dados POST
if [ "$REQUEST_METHOD" = "POST" ]; then
    read -r POST_DATA
else
    return_error "Metodo nao suportado. Use POST."
fi

# Decodificar URL
decode_url() {
    echo -e "$(echo "$1" | sed 's/+/ /g; s/%\([0-9a-fA-F][0-9a-fA-F]\)/\\x\1/g')"
}

# Parsear parametros POST
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
    
    # Exportar como variaveis globais
    ACTION="${PARSED[action]}"
    TEST_TYPE="${PARSED[test]}"
}

# Parsear dados recebidos
parse_params "$POST_DATA"

log_debug "Açao recebida: $ACTION"
log_debug "Tipo de teste: $TEST_TYPE"

# Executar açao baseada no parametro
case "$ACTION" in
    "full-diagnostic")
        log_debug "Executando diagnostico completo"
        
        # Executar o script completo
        if output=$($DIAGNOSTIC_SCRIPT 2>&1); then
            return_success "$output"
        else
            return_error "Erro ao executar diagnostico completo: $output"
        fi
        ;;
        
    "specific-test")
        log_debug "Executando teste especifico: $TEST_TYPE"
        
        case "$TEST_TYPE" in
    "storage")
        # Executar apenas testes de armazenamento (Testes 01 e 02)
        if output=$(timeout 300 bash -c "
        # Remover o source - executar diretamente
        
        # Executar apenas as seções de armazenamento
        echo '🔍 Teste 01: Verificando armazenamento...'
        
        # Verifica fstab vs montagens atuais
        echo \"   \$(date \"+%Y-%m-%d %H:%M:%S\") - Verificando consistência do /etc/fstab...\"
        
        # Usar teste de montagem sem executar
        if mount -a 2>/dev/null; then
            echo '✅ OK: Configuração do fstab está válida'
        else
            echo '⚠️  AVISO: Possíveis problemas na configuração do fstab'
            # Mostrar apenas os primeiros erros para não sobrecarregar
            mount_errors=\$(mount -a 2>&1 | head -3)
            if [ -n \"\$mount_errors\" ]; then
                echo \"Detalhes: \$mount_errors\"
            fi
        fi
        
        # Verificar montagens atuais sem sudo
        echo \"   \$(date \"+%Y-%m-%d %H:%M:%S\") - Verificando montagens atuais...\"
        missing_mounts=\$(awk '!/^#/ && NF>0 && \$3!=\"swap\" && \$2!=\"/\" && \$2!=\"none\" {print \$2}' /etc/fstab 2>/dev/null | while read mountpoint; do
            if [ -n \"\$mountpoint\" ] && ! mountpoint -q \"\$mountpoint\" 2>/dev/null; then
                echo \"Não montado: \$mountpoint\"
            fi
        done)
        
        if [ -n \"\$missing_mounts\" ]; then
            echo '⚠️  AVISO: Pontos de montagem não encontrados:'
            echo \"\$missing_mounts\"
        else
            echo '✅ OK: Todos os pontos de montagem críticos estão ativos'
        fi
        
        echo \"   \$(date \"+%Y-%m-%d %H:%M:%S\") - Verificando integridade dos sistemas de arquivos...\"
        fs_errors=\$(dmesg 2>/dev/null | grep -i \"ext[234]\\|xfs\\|btrfs\" | grep -i \"error\\|corrupt\\|remount.*read-only\" | tail -10)
        if [ -n \"\$fs_errors\" ]; then
            echo '❌ ERRO: Detectados erros no sistema de arquivos!'
            echo \"\$fs_errors\"
        else
            echo '✅ OK: Nenhum erro de sistema de arquivos detectado'
        fi
        
        echo '🔍 Teste 02: Verificando utilização de armazenamento...'
        
        # Verifica 100% de uso - melhor tratamento
        diskfull=\$(df -h 2>/dev/null | awk 'NR>1 && \$5 == \"100%\" {print \$0}')
        if [ -z \"\$diskfull\" ]; then
            echo '✅ OK: Nenhum disco com 100% de uso'
        else
            echo '❌ CRÍTICO: Armazenamento(s) lotado(s)!'
            echo \"\$diskfull\"
        fi
        
        # Verifica uso acima de 90% - correção na lógica AWK
        disk_high=\$(df -h 2>/dev/null | awk 'NR>1 && \$5 != \"-\" && \$5 != \"Use%\" && \$5 ~ /%/ {
            gsub(/%/, \"\", \$5); 
            if (\$5 >= 90) print \$0
        }')
        if [ -n \"\$disk_high\" ]; then
            echo '⚠️  AVISO: Armazenamento(s) com 90% ou mais de uso:'
            echo \"\$disk_high\"
        else
            echo '✅ OK: Nenhum disco com +90% de uso'
        fi
        
        # Informações de debug
        echo \"   \$(date \"+%Y-%m-%d %H:%M:%S\") - Resumo do armazenamento:\"
        df -h 2>/dev/null | head -10
        
        " 2>&1); then
            return_success "$output"
        else
            return_error "Erro ao executar teste de armazenamento: $output"
        fi
       ;;
                
            "network")
                # Executar apenas teste de rede (Teste 03)
                if output=$(timeout 180 bash -c "
                    echo '🔍 Teste 03: Verificando conectividade de rede...'
                    
                    dns_servers=('1.1.1.1' '8.8.8.8' '208.67.222.222')
                    dns_working=0
                    
                    for dns in \"\${dns_servers[@]}\"; do
                        ping_output=\$(ping -c 1 -W 2 \"\$dns\" 2>&1)
                        ping_status=\$?
                        
                        if [ \$ping_status -eq 0 ]; then
                            echo \"DNS \$dns respondendo!\"
                            echo \"\$ping_output\" | grep \"time=\"
                            ((dns_working++))
                        else
                            echo \"DNS \$dns nao esta acessivel!\"
                        fi
                    done
                    
                    # Verifica interfaces de rede
                    echo '   \$(date \"+%Y-%m-%d %H:%M:%S\") - Verificando interfaces de rede...'
                    network_down=\$(ip -o link show | awk '/state DOWN/ {print \$2,\$17}')
                    if [ -n \"\$network_down\" ]; then
                        echo 'AVISO: Interface(s) de rede inativa(s) detectadas:'
                        echo \"\$network_down\"
                    else
                        echo 'Todas as interfaces de rede existentes estao ativas!'
                    fi
                    
                    # Verifica resoluçao DNS
                    echo '   \$(date \"+%Y-%m-%d %H:%M:%S\") - Verificando resoluçao DNS...'
                    if ! nslookup google.com >/dev/null 2>&1; then
                        echo 'AVISO: Problemas na resoluçao DNS'
                    else
                        echo 'Resoluçao DNS OK'
                        meuipwan=\$(dig @resolver4.opendns.com myip.opendns.com +short 2>/dev/null || echo 'N/A')
                        meugateway=\$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'via \K\S+' || echo 'N/A')
                        meudevice=\$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'dev \K\S+' || echo 'N/A')
                        meuiplan=\$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || echo 'N/A')
                        echo \"IP WAN   : \$meuipwan\"
                        echo \"IP LAN   : \$meuiplan\"
                        echo \"Gateway  : \$meugateway\"
                        echo \"Interface: \$meudevice\"
                    fi
                " 2>&1); then
                    return_success "$output"
                else
                    return_error "Erro ao executar teste de rede"
                fi
                ;;
                
            "services")
                # Executar apenas teste de serviços (Teste 04)
                if output=$(timeout 120 bash -c "
                    echo '🔍 Teste 04: Verificando serviços essenciais...'
                    
                    # Lista de serviços criticos para verificar
                    critical_services=('ssh.socket' 'systemd-resolved' 'NetworkManager' 'cron')
                    
                    # Verifica serviços do sistema
                    for service in \"\${critical_services[@]}\"; do
                        if systemctl is-active --quiet \"\$service\" 2>/dev/null; then
                            echo \"OK: Serviço \$service esta ativo\"
                        else
                            if systemctl list-unit-files --type=service | grep -q \"^\$service\"; then
                                echo \"AVISO: Serviço \$service esta inativo\"
                            fi
                        fi
                    done
                    
                    # Testando Docker
                    echo '   \$(date \"+%Y-%m-%d %H:%M:%S\") - Verificando Docker...'
                    if systemctl is-active --quiet docker 2>/dev/null; then
                        echo 'OK: Docker esta ativo'
                        
                        if ! docker system df >/dev/null 2>&1; then
                            echo 'AVISO: Docker nao esta respondendo adequadamente'
                        else
                            echo 'OK: Docker esta respondendo aos comandos normalmente'
                        fi
                    elif command -v docker >/dev/null 2>&1; then
                        echo 'ERRO: Docker esta instalado mas nao esta executando!'
                    else
                        echo 'OK: Docker nao esta instalado'
                    fi
                    
                    # Testando LibVirt
                    echo '   \$(date \"+%Y-%m-%d %H:%M:%S\") - Verificando LibVirt...'
                    if systemctl is-active --quiet libvirtd 2>/dev/null; then
                        echo 'OK: LibVirt esta ativo'
                    elif command -v libvirtd >/dev/null 2>&1; then
                        echo 'AVISO: LibVirt esta instalado mas nao esta executando!'
                    else
                        echo 'OK: LibVirt nao esta instalado neste servidor'
                    fi
                " 2>&1); then
                    return_success "$output"
                else
                    return_error "Erro ao executar teste de serviços"
                fi
                ;;
                
            "system")
                # Executar apenas teste de sistema (Teste 05)
                if output=$(timeout 60 bash -c "
                    echo '🔍 Teste 05: Verificaçoes adicionais do sistema...'
                    
                    # Verifica carga do sistema
                    load_avg=\$(uptime | awk '{print \$(NF-2)}' | sed 's/,//')
                    cpu_cores=\$(nproc)
                    load_threshold=\$(echo \"\$cpu_cores * 2\" | bc -l 2>/dev/null || echo \"8\")
                    
                    if (( \$(echo \"\$load_avg > \$load_threshold\" | bc -l 2>/dev/null || echo \"0\") )); then
                        echo \"AVISO: Carga do sistema alta (\$load_avg com \$cpu_cores cores)\"
                    else
                        echo \"OK: Carga do sistema normal (\$load_avg)\"
                    fi
                    
                    # Verifica memoria
                    mem_usage=\$(free | awk 'NR==2{printf \"%.0f\", \$3*100/\$2}')
                    if [ \"\$mem_usage\" -gt 90 ]; then
                        echo \"ERRO: Uso de memoria critico (\${mem_usage}%)\"
                    elif [ \"\$mem_usage\" -gt 80 ]; then
                        echo \"AVISO: Uso de memoria alto (\${mem_usage}%)\"
                    else
                        echo \"OK: Uso de memoria normal (\${mem_usage}%)\"
                    fi
                    
                    # Verifica processos zumbis
                    zombies=\$(ps aux | awk '\$8 ~ /^Z/ { count++ } END { print count+0 }')
                    if [ \"\$zombies\" -gt 0 ]; then
                        echo \"AVISO: \$zombies processo(s) zumbi detectado(s)\"
                    else
                        echo \"OK: Nenhum processo zumbi detectado\"
                    fi
                    
                    # Verifica logs de erro recentes
                    echo '   \$(date \"+%Y-%m-%d %H:%M:%S\") - Verificando logs de sistema...'
                    recent_errors=\$(journalctl --since \"1 hour ago\" -p err -q --no-pager 2>/dev/null | wc -l)
                    if [ \"\$recent_errors\" -gt 10 ]; then
                        echo \"AVISO: \$recent_errors erros no log da ultima hora\"
                    else
                        echo \"OK: Poucos erros nos logs recentes\"
                    fi
                " 2>&1); then
                    return_success "$output"
                else
                    return_error "Erro ao executar teste de sistema"
                fi
                ;;
                
            *)
                return_error "Tipo de teste nao reconhecido: $TEST_TYPE"
                ;;
        esac
        ;;
        
    "system-info")
        log_debug "Coletando informaçoes do sistema"
        
        if output=$(timeout 30 bash -c "
            echo '📊 INFORMAÇoES DO SISTEMA'
            echo '=========================='
            echo ''
            echo '🖥️  Sistema Operacional:'
            if [ -f /etc/os-release ]; then
                source /etc/os-release
                echo \"   Distro: \$PRETTY_NAME\"
                echo \"   Versao: \$VERSION\"
            else
                echo '   Informaçoes nao disponiveis'
            fi
            echo ''
            
            echo '💻 Hardware:'
            echo \"   CPU: \$(nproc) nucleo(s)\"
            echo \"   Modelo: \$(cat /proc/cpuinfo | grep 'model name' | head -1 | cut -d: -f2 | sed 's/^ *//')\"
            echo \"   Memoria Total: \$(free -h | awk 'NR==2{print \$2}')\"
            echo \"   Memoria Usada: \$(free -h | awk 'NR==2{print \$3}')\"
            echo \"   Memoria Livre: \$(free -h | awk 'NR==2{print \$4}')\"
            echo ''
            
            echo '💾 Armazenamento:'
            df -h | grep -E '^/dev/' | while read line; do
                echo \"   \$line\"
            done
            echo ''
            
            echo '🔗 Rede:'
            ip -o link show | grep -E 'state UP' | while read line; do
                interface=\$(echo \$line | awk '{print \$2}' | sed 's/://')
                state=\$(echo \$line | awk '{print \$9}')
                echo \"   Interface \$interface: \$state\"
            done
            echo ''
            
            echo 'Sistema:'
            echo \"   Uptime: \$(uptime -p)\"
            echo \"   Data/Hora: \$(date)\"
            echo \"   Carga: \$(uptime | awk '{print \$(NF-2), \$(NF-1), \$NF}')\"
            echo ''
            
            echo '🔧 Serviços Principais:'
            services=('ssh' 'cron' 'systemd-resolved' 'NetworkManager')
            for service in \"\${services[@]}\"; do
                if systemctl is-active --quiet \$service 2>/dev/null; then
                    echo \"   \$service: Ativo\"
                else
                    echo \"   \$service: Inativo\"
                fi
            done
        " 2>&1); then
            return_success "$output"
        else
            return_error "Erro ao coletar informaçoes do sistema"
        fi
        ;;
        
    "quick-info")
        log_debug "Coletando informaçoes rapidas"
        
        if output=$(timeout 10 bash -c "
            echo \"Hostname: \$(hostname)\"
            echo \"Uptime: \$(uptime -p)\"
            echo \"Load: \$(uptime | awk '{print \$(NF-2)}' | sed 's/,//')\"
            echo \"Memory: \$(free | awk 'NR==2{printf \"%.0f%%\", \$3*100/\$2}')\"
            echo \"Disk: \$(df / | awk 'NR==2{print \$5}')\"
        " 2>&1); then
            return_success "$output"
        else
            return_error "Erro ao coletar informaçoes rapidas"
        fi
        ;;
        
    "ping")
        log_debug "Ping recebido"
        return_success "pong"
        ;;
        
    *)
        return_error "Açao nao reconhecida: $ACTION"
        ;;
esac

# Se chegou ate aqui, algo deu errado
return_error "Erro interno do script"
