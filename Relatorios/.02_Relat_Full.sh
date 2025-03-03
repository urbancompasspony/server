#!/bin/bash

TERM=xterm-256color

function cabecalho {
  [ -f "$file" ] || {
    sudo touch $setfolder/relatorio-$monthonly.txt

    echo "RELATÓRIO MENSAL DE PRESTAÇÃO DE SERVIÇOS DE INFORMÁTICA
" | sudo tee "$file"
    echo "Conforme estipulado em contrato mensal de prestação de serviços na área de
informática, segue abaixo o relatório de manutenções preventivas e
corretivas executados no servidor no período de $monthonly:
" | sudo tee -a "$file"
    sleep 1
  } && {
    echo "." > /dev/null
  }
}

function upgrade0 {
  datetime0
  export DEBIAN_FRONTEND=noninteractive
  echo ""; echo "Atualizando o sistema!"; echo ""
  sudo apt update -y &&
  sudo apt upgrade -y &&
  sudo apt autoremove -y &&
  echo ""; echo "Em $datetime o sistema do servidor foi atualizado e está em dia com a segurança digital.
" | sudo tee -a "$file"
}

function smartdump0 {
  datetime0
  smartdump1
  echo ""; echo "Em $datetime foi realizada a verificação da saúde dos discos rígidos.
Mais informações no anexo SMART_DUMP no e-mail!
" | sudo tee -a "$file"
}

function smartdump1 {
  datetime0
  sudo rm $smartdumplocal
  sudo touch $smartdumplocal

  for i in {a..z}
  do
    # Check if block device exist
    [ -b /dev/sd$i ] && {
      echo ""; echo "############################################################################"; echo "Armazenamento: /dev/sd$i"; echo ""
      sudo smartctl -a -T permissive -T permissive /dev/sd$i | grep -a "Model Family:" | sudo tee -a $smartdumplocal
      sudo smartctl -a -T permissive -T permissive /dev/sd$i | grep -a "Device Model:" | sudo tee -a $smartdumplocal
      sudo smartctl -a -T permissive -T permissive /dev/sd$i | grep -a "Serial Number:" | sudo tee -a $smartdumplocal
      echo ""
      sudo smartctl -A -T permissive -T permissive /dev/sd$i | sudo tee -a $smartdumplocal
      echo ""
    } || {
      echo "." >/dev/null
    }
  done

  for i in {0..10}
  do
    # Check if block device exist
    [ -b /dev/nvme0n1p$i ] && {
        echo ""; echo "############################################################################"; echo "Armazenamento: /dev/nvme0n1p$i"; echo ""
        sudo smartctl -a -T permissive -T permissive /dev/nvme0n1p$i | grep -a "Model Number:" | sudo tee -a $smartdumplocal
        sudo smartctl -a -T permissive -T permissive /dev/nvme0n1p$i | grep -a "Serial Number:" | sudo tee -a $smartdumplocal
        echo ""
        sudo smartctl -A -T permissive -T permissive /dev/nvme0n1p$i | sudo tee -a $smartdumplocal
        echo ""
    } || {
      echo "." >/dev/null
    }
  done

  for i in {0..5}
  do
    # Check if block device exist
    [ -c /dev/sg$i ] && {
    for j in {0..10}
      do
        testraid=$(sudo smartctl -d megaraid,$j -A -T permissive -T permissive /dev/sg$i | grep failed)
        # Check if SMART data exist for that block device
        [ "$testraid" = "" ] && {
          echo ""; echo "############################################################################"; echo ""; echo "RAID ID: $j"; echo ""
          sudo smartctl -d megaraid,$j -a -T permissive -T permissive /dev/sg$i | grep -a "Model Family:" | sudo tee -a $smartdumplocal
          sudo smartctl -d megaraid,$j -a -T permissive -T permissive /dev/sg$i | grep -a "Device Model:" | sudo tee -a $smartdumplocal
          sudo smartctl -d megaraid,$j -a -T permissive -T permissive /dev/sg$i | grep -a "Serial Number:" | sudo tee -a $smartdumplocal
          echo ""
          sudo smartctl -d megaraid,$j -A -T permissive -T permissive /dev/sg$i | sudo tee -a $smartdumplocal
          echo ""
        } || {
          echo "." >/dev/null
        }
      done
    } || {
      echo "." >/dev/null
    }
done

echo "" | sudo tee -a $smartdumplocal
echo ""; echo "Verificacao concluida em $datetime!" | sudo tee -a $smartdumplocal
}

function domain0 {
  [ -d "/srv/containers/dominio" ] && {
  datetime0
  docker exec dominio samba-tool ntacl sysvolreset -U Administrator
  docker exec dominio samba-tool dbcheck --cross-ncs --reset-well-known-acls --fix --yes

  echo ""; echo "Em $datetime foi realizada a verificação da integridade do Controlador de Domínio.
" | sudo tee -a "$file"

  } || {
    echo "." >/dev/null
  }
}

function pihole0 {
  testpihole=$(docker image ls | grep -a "pihole")

  [ "$testpihole" = "" ] || {
    datetime0
    echo ""; echo "Checando por updates do PiHole"
    docker pull pihole/pihole:latest

    for i in $(find /srv/containers -maxdepth 1 -name '*pihole*'); do
      i2=$(basename "$i")

      docker exec "$i2" bash -c "rm /etc/pihole/pihole-FTL.db"

      var1=$(sed -n '1p' /srv/containers/"$i2"/Information)
      var2=$(sed -n '2p' /srv/containers/"$i2"/Information)
      var3=$(sed -n '3p' /srv/containers/"$i2"/Information)
      var4=$(sed -n '4p' /srv/containers/"$i2"/Information)
      var5=$(sed -n '5p' /srv/containers/"$i2"/Information)
      var6=$(sed -n '6p' /srv/containers/"$i2"/Information)

      pihole1

      echo ""; echo "Esperar 5s antes de aplicar as configs"; sleep 5
      docker exec "$i2" pihole-FTL --config misc.etc_dnsmasq_d true

      docker exec "$i2" rm /etc/pihole/pihole-FTL.conf
      docker exec "$i2" sudo touch /etc/pihole/pihole-FTL.conf
      docker exec "$i2" bash -c "echo 'LOCAL_IPV4=0.0.0.0' >> /etc/pihole/pihole-FTL.conf"
      docker exec "$i2" bash -c "echo 'RATE_LIMIT=0/0' >> /etc/pihole/pihole-FTL.conf"

      [ -f /srv/containers/"$i2"/dnsmasq.d/02-custom-settings.conf ] || {
        docker exec "$i2" bash -c "echo '# domain forward lookups' > /etc/dnsmasq.d/02-custom-settings.conf"
        docker exec "$i2" bash -c "echo '#server=/ad.domain.local/191.168.0.10' >> /etc/dnsmasq.d/02-custom-settings.conf"
        docker exec "$i2" bash -c "echo '# domain PTR/reverse lookups' >> /etc/dnsmasq.d/02-custom-settings.conf"
        docker exec "$i2" bash -c "echo '#server=/0.168.192.in-addr.arpa/192.168.0.10' >> /etc/dnsmasq.d/02-custom-settings.conf"
        docker exec "$i2" bash -c "echo '# Custom DNS Max Queries and Cache' >> /etc/dnsmasq.d/02-custom-settings.conf"
        docker exec "$i2" bash -c "echo 'dns-forward-max=5096' >> /etc/dnsmasq.d/02-custom-settings.conf"
        docker exec "$i2" bash -c "echo 'min-cache-ttl=300' >> /etc/dnsmasq.d/02-custom-settings.conf"
        docker exec "$i2" bash -c "echo 'rebind-domain-ok=' >> /etc/dnsmasq.d/02-custom-settings.conf"
      } && {
        echo "." >/dev/null
      }

      docker restart "$i2"

      echo ""; echo "Em $datetime os serviços de DNS e bloqueios de sites do $i2 foram atualizados e suas listas foram revalidadas!
" | sudo tee -a "$file"
    done
  } && {
    echo "." > /dev/null
  }
}

function pihole1 {
  docker stop "$i2" &&
  docker rm "$i2" &&

  [ "$var1" = "host" ] || [ "$var1" = "Host" ] || [ "$var1" = "HOST" ] || [ "$var1" = "hostname" ] || [ "$var1" = "localhost" ] && {
  docker run -d \
--name="$i2" \
--network host \
--hostname="$var4" \
--no-healthcheck \
--restart=unless-stopped \
--shm-size=512m \
-e FTLCONF_webserver_api_password=$var2 \
-e FTLCONF_dns_listeningMode=all \
-e TZ=$var6 \
-v /etc/localtime:/etc/localtime:ro \
-v /srv/containers/"$i2"/etc/:/etc/pihole \
-v /srv/containers/"$i2"/dnsmasq.d/:/etc/dnsmasq.d \
-v /srv/containers/"$i2"/log/:/var/log/pihole \
-p 80:80 \
-p 443:443 \
-p 67:67/tcp \
-p 67:67/udp \
-p 53:53/tcp \
-p 53:53/udp \
pihole/pihole:latest
  } || {
  docker run -d \
--name="$i2" \
--network $var5 \
--ip=$var1 \
--dns=1.1.1.1  \
--hostname="$var4" \
--no-healthcheck \
--restart=unless-stopped \
--shm-size=512m \
-e FTLCONF_webserver_api_password=$var2 \
-e FTLCONF_dns_listeningMode=all \
-e TZ=$var6 \
-v /etc/localtime:/etc/localtime:ro \
-v /srv/containers/"$i2"/etc/:/etc/pihole \
-v /srv/containers/"$i2"/dnsmasq.d/:/etc/dnsmasq.d \
-v /srv/containers/"$i2"/log/:/var/log/pihole \
-p 80:80 \
-p 443:443 \
-p 67:67/tcp \
-p 67:67/udp \
-p 53:53/tcp \
-p 53:53/udp \
pihole/pihole:latest
  }
}

function pentest0 {
  [ -d "/srv/containers/pentest" ] && {
    datetime0
    [ -f /srv/containers/pentest/Pentests/Ransomware_Detectado ] && {
      echo ""
      cat /srv/containers/pentest/Pentests/Ransomware_Detectado
    } || {
      echo "." > /dev/null
    }

    var6=$(sed -n '6p' /srv/containers/pentest/Information)

    for i in $(find /srv/containers/pentest/Pentests/Ataques_Bem-sucedidos -name '*1*'); do
      cat "$i"
    done

    echo ""; echo "Em $datetime nenhum novo equipamento vulnerável detectado na rede.
Por enquanto nenhum equipamento cujos testes sejam pertinentes de serem notificados.
" | sudo tee -a "$file"

  } || {
    echo ""; echo "Pentest não configurado. Ignorando."
    sleep 3
  }
}

function syslog0 {
  datetime0

  for i in $(ls /srv/containers/*/log/syslog); do
    echo ""; echo "$i"; echo ""
    cat $i | grep -a 'renameat' | tail -n 7
  done

  echo ""; echo "Em $datetime foi realizada a verificação da integridade dos Logs de Eventos
das pastas da rede e se os registros de uso, dos compartilhamentos, estão em dia.
" | sudo tee -a "$file"
}

function backup0 {
  datetime0
  echo ""; echo "Checando armazenamento geral!"; echo ""
  df -h

  echo ""; echo "DUMP de RSnapshots!"; echo ""
  journalctl -b 0 | grep -a "rsnap" | tail -n 7

  echo ""; echo "DUMP de RSYNC!"; echo ""
  journalctl -b 0 | grep -a "rsync" | tail -n 7

  echo ""; echo "DUMP do RClone (se existente)!"; echo ""
  journalctl -b 0 | grep -a "rclone" | tail -n 7

  echo ""; echo "Checando backups dos containers!"; echo ""

  destiny=$(sed -n '2p' /srv/containers/scripts/config/backupcont)
  [ -d "$destiny" ] && {
    ls -lah $destiny
  } || {
    echo ""; echo "Não existem backups de containers neste servidor! Verifique se esta situação está correta!"; echo ""
  }

  echo "Em $datetime foi realizada a verificação das rotinas de backup do servidor.
O backup para a nuvem, se existente, também foi verificado.
" | sudo tee -a "$file"
}

function contclean0 {
  docker image prune -a -f

  echo ""; echo "Em $datetime foi realizada a limpeza do sistema com remoção de somente pacotes e
imagens obsoletas dos serviços, objetivando reduzir o consumo de armazenamento.
" | sudo tee -a "$file"
}

function swap0 {
  sudo swapoff -a &&
  sudo swapon -a &&
}

function datetime0 {
  datetime=$(date +"%d/%m")
}

# NOT USED. But keep here bcuz I like it.
function relatend0 {
  echo ""; echo "=============================================================================================="
  echo ""; echo "RELATORIO RESUMIDO"
  echo ""; echo "=============================================================================================="
  echo ""; echo "SMART_DUMP:"
  echo ""; cat $smartdumplocal
  echo ""; echo "=============================================================================================="
  echo ""; cat $setfolder/relatorio-$monthonly.txt
  echo "=============================================================================================="
  echo ""
}

###############
# Start here! #
###############

setfolder="/srv/relatorios"
smartdumplocal="$setfolder/SMART_DUMP"
sudo mkdir -p $setfolder

monthonly=$(date +"%m-%Y")
file="$setfolder/relatorio-$monthonly.txt"

# Swap Off and On
sudo swapoff -a && sudo swapon -a &&

swap0
cabecalho
upgrade0
smartdump0
domain0
pihole0
pentest0
syslog0
backup0
contclean0
swap0

exit 1
