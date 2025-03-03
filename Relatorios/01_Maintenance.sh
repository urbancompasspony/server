#!/bin/bash

SCRIPT0=".02_Relat_Full.sh"
SERVER_LIST=".03_Servers.txt"
PASSWORD_LIST=".04_Passwords.txt"
EVENT_LOG=".05_Event_Log.txt"
REMOTE_PORT=22

# Verificar se o arquivo de servidores existe e pode ser lido

if [ ! -f "$SERVER_LIST" ]; then
    echo "Erro: O arquivo de servidores '$SERVER_LIST' não existe."
    exit 1
fi

if [ ! -r "$SERVER_LIST" ]; then
    echo "Erro: O arquivo de servidores '$SERVER_LIST' não pode ser lido."
    exit 1
fi

# Verificar se o arquivo de senhas existe e pode ser lido

if [ ! -f "$PASSWORD_LIST" ]; then
    echo "Erro: O arquivo de senhas '$PASSWORD_LIST' não existe."
    exit 1
fi

if [ ! -r "$PASSWORD_LIST" ]; then
    echo "Erro: O arquivo de senhas '$PASSWORD_LIST' não pode ser lido."
    exit 1
fi

# Ler os arquivos de servidores e senhas em arrays
mapfile -t servers < "$SERVER_LIST"
mapfile -t passwords < "$PASSWORD_LIST"

# Verificar se há a mesma quantidade de servidores e senhas
if [ "${#servers[@]}" -ne "${#passwords[@]}" ]; then
    echo "Erro: A quantidade de servidores e senhas não corresponde."
    exit 1
fi

# Loop sobre os servidores e senhas
for i in "${!servers[@]}"; do
    server="${servers[$i]}"
    password="${passwords[$i]}"

    REMOTE_USER=$(echo "$server" | cut -d'@' -f1)
    REMOTE_HOST=$(echo "$server" | cut -d'@' -f2)

    echo "Verificando conectividade com $REMOTE_HOST..."

    if ping -c 1 -W 2 "$REMOTE_HOST" > /dev/null 2>&1; then
      echo "Conectividade OK. Conectando a $REMOTE_USER@$REMOTE_HOST..."

      scp -P "$REMOTE_PORT" "$SCRIPT0" "$REMOTE_USER@$REMOTE_HOST:/tmp/$SCRIPT0"
      mkdir -p "$REMOTE_HOST"

      ssh $REMOTE_USER@$REMOTE_HOST -p $REMOTE_PORT "sshpass -p '$password' bash /tmp/$SCRIPT0" | tee $REMOTE_HOST/"Registro de Eventos.txt"
      ssh $REMOTE_USER@$REMOTE_HOST -p $REMOTE_PORT "cat /srv/relatorios/relatorio-$(date +'%m-%Y').txt" | tee $REMOTE_HOST/"Relatório de Manutenção.txt"
      ssh $REMOTE_USER@$REMOTE_HOST -p $REMOTE_PORT "cat /srv/relatorios/SMART_DUMP" | tee $REMOTE_HOST/"Saude do Armazenamento (SMART_DUMP).txt"
    else
      echo "$(date) Erro tentando conectar ao servidor $REMOTE_HOST." | tee -a "$EVENT_LOG"
    fi
done
