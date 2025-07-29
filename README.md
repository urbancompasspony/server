# Ubuntu Server Manager (USM) v5.3

## 📖 Sobre

O **Ubuntu Server Manager (USM)** é um script bash interativo desenvolvido por José Humberto que oferece uma interface amigável para gerenciar servidores Ubuntu. Com menus organizados e funcionalidades práticas, o USM simplifica tarefas complexas de administração de servidor.

## ✨ Características Principais

- 🔐 **Sistema de autenticação** com múltiplos níveis de acesso
- 🐳 **Gerenciamento Docker** completo (orquestração e manutenção)
- 🖥️ **Interface gráfica** com suporte a Wayland (LabWC)
- 🌐 **Configuração de rede** via Netplan
- 🏢 **Integração Active Directory** 
- 📊 **Ferramentas de diagnóstico** do sistema
- 🔄 **Continuidade de negócio** (CDN)
- 🛠️ **Ferramentas diversas** para manutenção

## 🚀 Como Usar

### Instalação e Execução
```bash
# Apenas executar:
srv

# Baixar e executar o script caso não exista no sistema:
curl -sSL srv.linuxuniverse.com.br | bash

# Ou salvar localmente
wget https://raw.githubusercontent.com/urbancompasspony/server/main/srv
chmod +x srv
./srv
```

### Primeiro Acesso
1. Execute o script
2. Digite a senha quando solicitado
3. Navegue pelos menus usando as setas do teclado
4. Pressione Enter para selecionar uma opção

## 📋 Funcionalidades

### Menu Principal (Supervisor)
- **Docker Orchestration** - Gerenciamento avançado de containers
- **Docker Maintenance** - Ferramentas de manutenção Docker
- **AutoConfig pfSense (VM)** - Configuração automática pfSense
- **DWAgent (ARM)** - Instalação do agente DWService
- **Set Wayland (labwc)** - Configuração do ambiente Wayland
- **Netplan Menu** - Configuração de rede
- **Install DiagnosticUI** - Interface de diagnóstico
- **Install AD-DC-WebUI** - Interface web para Active Directory

### Menu de Suporte (Managers)
- **Informações do Servidor** - Dados detalhados do sistema
- **Área de Trabalho** - Acesso ao desktop local
- **Active Directory** - Gerenciamento de domínio
- **Ferramentas Diversas** - Utilitários variados
- **Diagnóstico do Sistema** - Análise completa do servidor
- **Continuidade do Negócio** - Ferramentas CDN
- **Controles de Sistema** - Reiniciar/Desligar

## 🔧 Requisitos

- **Sistema Operacional**: Ubuntu Server
- **Privilégios**: Usuário com sudo (não executar como root)
- **Dependências**: 
  - `dialog` (interface de menu)
  - `curl` ou `wget` (downloads)
  - `docker` (para funcionalidades Docker)

### Instalação de Dependências
```bash
sudo apt update
sudo apt install dialog curl wget -y
```

## 🛡️ Segurança

- O script utiliza hashes MD5 para autenticação
- Diferentes níveis de acesso baseados em senhas
- Verificação automática de execução como root (bloqueada)
- Timeout progressivo para tentativas de senha incorretas

## 📊 Informações do Sistema

O USM pode exibir informações detalhadas quando configurado com arquivo `/srv/system.yaml`:
- IP WAN e LAN atuais
- Gateway e subnet identificados
- Informações de hardware
- Configurações personalizadas

## 🎨 Interface

- **Menu interativo** com navegação por setas
- **Caixas de diálogo** para confirmações
- **Visualização paginada** para informações extensas
- **Feedback visual** para operações em andamento

## 🔄 Atualizações Automáticas

O script verifica e atualiza automaticamente o bashrc na primeira execução, garantindo compatibilidade e melhorias contínuas.

## ⚠️ Avisos Importantes

1. **Não execute com sudo** - O script detecta e bloqueia execução como root
2. **Desktop remoto** - A função desktop só funciona localmente
3. **Dependências Docker** - Algumas funcionalidades requerem Docker instalado
4. **Backup** - Sempre faça backup antes de alterações críticas

## 🎯 Casos de Uso

- **Administradores de sistema** que precisam de uma interface unificada
- **Empresas** que gerenciam múltiplos servidores Ubuntu
- **Ambientes corporativos** com Active Directory
- **Infraestruturas containerizadas** com Docker
- **Configuração rápida** de novos servidores

---

*Este README foi gerado com base no script USM v5.3. Para mais informações e atualizações, consulte o repositório oficial.*
