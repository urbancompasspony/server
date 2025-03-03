#!/bin/bash

SCRIPT0=".02_Relat_Full.sh"

SERVER_LIST=".03_Serversb.txt"

PASSWORD_LIST=".04_Passwordsb.txt"

REMOTE_PORT=22

while IFS= read -r server && IFS= read -r password <&3; do
    REMOTE_USER=$(echo $server | cut -d'@' -f1)
    REMOTE_HOST=$(echo $server | cut -d'@' -f2)

    echo "Verificando conectividade com $REMOTE_HOST..."

    if ping -c 1 -W 2 $REMOTE_HOST > /dev/null 2>&1; then

        echo "Conectividade OK. Conectando a $REMOTE_USER@$REMOTE_HOST..."

        scp -P $REMOTE_PORT $SCRIPT0 $REMOTE_USER@$REMOTE_HOST:/tmp/$SCRIPT0

        ssh $REMOTE_USER@$REMOTE_HOST -p $REMOTE_PORT "sshpass -p '$password' bash /tmp/$SCRIPT0" | tee "${REMOTE_HOST}_Registro_Completo_de_Eventos.txt"

        ssh $REMOTE_USER@$REMOTE_HOST -p $REMOTE_PORT "cat /srv/relatorios/relatorio-$(date +'%m-%Y').txt" | tee "${REMOTE_HOST}_Relatorio_de_Manutenção.txt"

        ssh $REMOTE_USER@$REMOTE_HOST -p $REMOTE_PORT "cat /srv/relatorios/SMART_DUMP" | tee "${REMOTE_HOST}_SMART_DUMP.txt"

        if [ $? -eq 0 ]; then
            echo "Comando executado com sucesso em $REMOTE_USER@$REMOTE_HOST."
        else
            echo "Falha ao executar em $REMOTE_USER@$REMOTE_HOST, por favor verifique o sistema manualmente."
        fi
    else
        echo "Falha na conectividade com $REMOTE_HOST. Ignorando este servidor."
    fi

done < "$SERVER_LIST" 3< "$PASSWORD_LIST"
