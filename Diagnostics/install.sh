#!/bin/bash

# Script de Instalação do Sistema de Diagnóstico WebUI
# install-diagnostic-webui.sh
# Versão: 1.0

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para log
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Verificar se está rodando como root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Este script deve ser executado como root (sudo)"
        exit 1
    fi
}

# Detectar servidor web
detect_webserver() {
    if systemctl is-active --quiet apache2 2>/dev/null; then
        WEBSERVER="apache2"
        WEBROOT="/var/www/html"
        CGI_DIR="/usr/lib/cgi-bin"
    elif systemctl is-active --quiet nginx 2>/dev/null; then
        WEBSERVER="nginx"
        WEBROOT="/var/www/html"
        CGI_DIR="/usr/lib/cgi-bin"
        log_warning "Nginx detectado. Será necessário configuração manual do CGI."
    elif systemctl is-active --quiet lighttpd 2>/dev/null; then
        WEBSERVER="lighttpd"
        WEBROOT="/var/www/html"
        CGI_DIR="/usr/lib/cgi-bin"
    else
        log_warning "Nenhum servidor web ativo detectado. Tentando instalar Apache..."
        install_apache
        WEBSERVER="apache2"
        WEBROOT="/var/www/html"
        CGI_DIR="/usr/lib/cgi-bin"
    fi
    
    log_success "Servidor web detectado: $WEBSERVER"
    log "Diretório web: $WEBROOT"
    log "Diretório CGI: $CGI_DIR"
}

# Instalar Apache
install_apache() {
    log "Instalando Apache..."
    
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y apache2
        a2enmod cgi
        systemctl enable apache2
        systemctl start apache2
    elif command -v yum >/dev/null 2>&1; then
        yum install -y httpd
        systemctl enable httpd
        systemctl start httpd
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y httpd
        systemctl enable httpd
        systemctl start httpd
    else
        log_error "Gerenciador de pacotes não suportado"
        exit 1
    fi
    
    log_success "Apache instalado e configurado"
}

# Instalar dependências
install_dependencies() {
    log "Instalando dependências..."
    
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y bc curl dnsutils smartmontools
    elif command -v yum >/dev/null 2>&1; then
        yum install -y bc curl bind-utils smartmontools
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y bc curl bind-utils smartmontools
    else
        log_warning "Gerenciador de pacotes não suportado. Instale manualmente: bc, curl, bind-utils/dnsutils, smartmontools"
    fi
    
    log_success "Dependências instaladas"
}

# Criar diretórios necessários
create_directories() {
    log "Criando diretórios necessários..."
    
    mkdir -p "$WEBROOT"
    mkdir -p "$CGI_DIR"
    mkdir -p "/usr/local/bin"
    mkdir -p "/var/log/diagnostic-webui"
    
    log_success "Diretórios criados"
}

create_diagnostic_script() {
    log "Criando script de diagnóstico..."
    
    if sudo wget https://raw.githubusercontent.com/urbancompasspony/server/refs/heads/main/Diagnostics/diagnostic-system.sh -O /usr/local/bin/diagnostic-system.sh; then
      chmod +x /usr/local/bin/diagnostic-system.sh
      log_success "Script diagnóstico criado com sucesso"
    else
      log_error "Falha ao baixar script diagnóstico. Verifique a conexão com internet."
      exit 1
    fi
}

create_cgi_script() {
    log "Criando script CGI..."
    
    if sudo wget https://raw.githubusercontent.com/urbancompasspony/urbancompasspony.github.io/refs/heads/main/system-diagnostic/system-diagnostic.cgi -O "$CGI_DIR/system-diagnostic.cgi"; then
      chmod +x "$CGI_DIR/system-diagnostic.cgi"
      log_success "Script CGI criado em $CGI_DIR/system-diagnostic.cgi"
    else
      log_error "Falha ao baixar script CGI. Verifique a conexão com internet."
      exit 1
    fi
}

create_html_page() {
    log "Criando página HTML..."
    
    # Verificar cada download individualmente
    if sudo wget https://raw.githubusercontent.com/urbancompasspony/server/refs/heads/main/Diagnostics/index.html -O "$WEBROOT/index.html" && \
       sudo wget https://raw.githubusercontent.com/urbancompasspony/server/refs/heads/main/Diagnostics/style.css -O "$WEBROOT/style.css" && \
       sudo wget https://raw.githubusercontent.com/urbancompasspony/server/refs/heads/main/Diagnostics/script.js -O "$WEBROOT/script.js"; then
       log_success "Página HTML criada em $WEBROOT/index.html"
    else
       log_error "Falha ao baixar arquivos HTML. Verifique a conexão com internet."
       exit 1
    fi
}

# Configurar permissões
configure_permissions() {
    log "Configurando permissões..."
    
    # Permissões para o script de diagnóstico
    chmod +x /usr/local/bin/diagnostic-system.sh
    
    # Permissões para o CGI
    chmod +x "$CGI_DIR/system-diagnostic.cgi"
    chown www-data:www-data "$CGI_DIR/system-diagnostic.cgi" 2>/dev/null || \
    chown apache:apache "$CGI_DIR/system-diagnostic.cgi" 2>/dev/null || \
    chown nginx:nginx "$CGI_DIR/system-diagnostic.cgi" 2>/dev/null || true
    
    # Permissões para logs
    chmod 755 /var/log/diagnostic-webui
    chown www-data:www-data /var/log/diagnostic-webui 2>/dev/null || \
    chown apache:apache /var/log/diagnostic-webui 2>/dev/null || \
    chown nginx:nginx /var/log/diagnostic-webui 2>/dev/null || true
    
    # Permissões para a página HTML
    chmod 644 "$WEBROOT/index.html"
    chown www-data:www-data "$WEBROOT/index.html" 2>/dev/null || \
    chown apache:apache "$WEBROOT/index.html" 2>/dev/null || \
    chown nginx:nginx "$WEBROOT/index.html" 2>/dev/null || true
    
    log_success "Permissões configuradas"
}

# Adicionar configuração de porta personalizada
configure_apache() {
    if [ "$WEBSERVER" = "apache2" ]; then
        log "Configurando Apache para porta 1298..."
        
        # Configurar porta customizada
        echo "Listen 1298" >> /etc/apache2/ports.conf
        
        # Criar VirtualHost para porta 1298
        cat > /etc/apache2/sites-available/diagnostic-1298.conf << 'EOFVHOST'
<VirtualHost *:1298>
    DocumentRoot /var/www/html
    ServerName localhost
    
    <Directory "/var/www/html">
        AllowOverride None
        Options Indexes FollowSymLinks
        Require all granted
    </Directory>
    
    <Directory "/usr/lib/cgi-bin">
        AllowOverride None
        Options +ExecCGI
        AddHandler cgi-script .cgi
        Require all granted
    </Directory>
    
    ScriptAlias /cgi-bin/ /usr/lib/cgi-bin/
</VirtualHost>
EOFVHOST

        # Habilitar o site
        a2ensite diagnostic-1298.conf
        a2dissite 000-default.conf
        
        # Verificar se CGI já está habilitado
        if ! apache2ctl -M 2>/dev/null | grep -q cgi_module; then
            a2enmod cgi
            log "Módulo CGI habilitado no Apache"
        fi
        
        # Reiniciar Apache
        systemctl restart apache2
        log_success "Apache configurado para porta 1298 e reiniciado"
    fi
}

# Configurar sudoers para permitir execução sem senha
configure_sudoers() {
    log "Configurando sudoers para execução CGI..."
    
    # Criar arquivo sudoers específico
    cat > /etc/sudoers.d/diagnostic-webui << 'EOFSUDO'
# Permitir que o usuário do servidor web execute comandos necessários para diagnóstico
www-data ALL=(root) NOPASSWD: /usr/local/bin/diagnostic-system.sh
www-data ALL=(root) NOPASSWD: /bin/mount
www-data ALL=(root) NOPASSWD: /usr/sbin/smartctl
www-data ALL=(root) NOPASSWD: /usr/bin/virsh
apache ALL=(root) NOPASSWD: /usr/local/bin/diagnostic-system.sh
apache ALL=(root) NOPASSWD: /bin/mount
apache ALL=(root) NOPASSWD: /usr/sbin/smartctl
apache ALL=(root) NOPASSWD: /usr/bin/virsh
nginx ALL=(root) NOPASSWD: /usr/local/bin/diagnostic-system.sh
nginx ALL=(root) NOPASSWD: /bin/mount
nginx ALL=(root) NOPASSWD: /usr/sbin/smartctl
nginx ALL=(root) NOPASSWD: /usr/bin/virsh
EOFSUDO

    chmod 440 /etc/sudoers.d/diagnostic-webui
    
    # Testar configuração sudoers
    if ! visudo -c -f /etc/sudoers.d/diagnostic-webui; then
        log_error "Erro na configuração do sudoers"
        rm -f /etc/sudoers.d/diagnostic-webui
        exit 1
    fi
    
    log_success "Sudoers configurado"
}

# Criar arquivo de configuração
create_config_file() {
    log "Criando arquivo de configuração..."
    
    cat > /etc/diagnostic-webui.conf << EOFCONFIG
# Configuração do Sistema de Diagnóstico WebUI
# /etc/diagnostic-webui.conf

# Versão
VERSION="1.0"

# Caminhos
DIAGNOSTIC_SCRIPT="/usr/local/bin/diagnostic-system.sh"
CGI_SCRIPT="$CGI_DIR/system-diagnostic.cgi"
HTML_PAGE="$WEBROOT/index.html"
LOG_DIR="/var/log/diagnostic-webui"

# Servidor Web
WEBSERVER="$WEBSERVER"
WEBROOT="$WEBROOT"
CGI_DIR="$CGI_DIR"

# Data de instalação
INSTALL_DATE="$(date)"
EOFCONFIG

    chmod 644 /etc/diagnostic-webui.conf
    log_success "Arquivo de configuração criado em /etc/diagnostic-webui.conf"
}

# Testar instalação
test_installation() {
    log "Testando instalação..."
    
    # Testar script de diagnóstico
    if [ -x /usr/local/bin/diagnostic-system.sh ]; then
        log_success "Script de diagnóstico: OK"
    else
        log_error "Script de diagnóstico: FALHA"
        exit 1
    fi
    
    # Testar script CGI
    if [ -x "$CGI_DIR/system-diagnostic.cgi" ]; then
        log_success "Script CGI: OK"
    else
        log_error "Script CGI: FALHA"
        exit 1
    fi
    
    # Testar página HTML
    if [ -f "$WEBROOT/index.html" ]; then
        log_success "Página HTML: OK"
    else
        log_error "Página HTML: FALHA"
        exit 1
    fi
    
    # Testar servidor web
    if systemctl is-active --quiet "$WEBSERVER" 2>/dev/null; then
        log_success "Servidor web ($WEBSERVER): OK"
    else
        log_warning "Servidor web ($WEBSERVER): Não está rodando"
    fi
    
    log_success "Todos os testes passaram!"
}

# Exibir informações finais
show_final_info() {
    echo ""
    echo "=============================================="
    log_success "INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
    echo "=============================================="
    echo ""
    echo -e "${GREEN}📋 Informações da Instalação:${NC}"
    echo -e "   🌐 Servidor Web: $WEBSERVER"
    echo -e "   📁 Diretório Web: $WEBROOT"
    echo -e "   🔧 Diretório CGI: $CGI_DIR"
    echo -e "   📄 Página HTML: $WEBROOT/index.html"
    echo -e "   🔌 Porta: 1298"
    echo ""
    echo -e "${BLUE}🔗 Acesso ao Sistema:${NC}"
    echo -e "   http://localhost:1298/index.html"
    echo -e "   http://$(hostname -I | awk '{print $1}'):1298/index.html"
    echo ""
    # ... resto da função
}

# Função principal
main() {
    echo "=============================================="
    echo "  INSTALADOR DO SISTEMA DE DIAGNÓSTICO WEBUI"
    echo "=============================================="
    echo ""
    
    check_root
    detect_webserver
    install_dependencies
    create_directories
    create_diagnostic_script
    create_cgi_script
    create_html_page
    configure_permissions
    configure_apache
    configure_sudoers
    create_config_file
    test_installation
    show_final_info
}

# Executar instalação
main "$@"
