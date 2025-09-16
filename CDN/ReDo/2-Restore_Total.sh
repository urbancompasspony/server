#!/bin/bash

sudo mkdir -p /srv/containers
sudo mkdir -p /mnt/bkpsys
sudo mount -t ext4 LABEL=bkpsys /mnt/bkpsys

pathrestore=$(find /mnt/bkpsys -name "*.tar.lz4" 2>/dev/null | head -1 | xargs dirname)

if ! [ -f /srv/restored1.lock ]; then
  datetime0=$(date +"%d/%m/%Y - %H:%M")
  sudo yq -i ".Informacoes.Data_Restauracao = \"${datetime0}\"" /srv/system.yaml

  sudo rsync -va $pathrestore/system.yaml /srv/system.yaml
  sudo rsync -va $pathrestore/containers.yaml /srv/containers.yaml

  find $pathrestore -type f -name "*.tar.lz4" -not -name "etc*.tar.lz4" -mtime -1 -print0 | \
  while IFS= read -r -d '' file; do
    echo "Restaurando: $file"
    sudo tar -I 'lz4 -d -c -' -xf "$file" -C "$DESTINO"
    echo "Concluído: $(basename "$file")"
  done

  # Fazer backup atual do /etc antes de restaurar
  echo "Criando backup de segurança do /etc atual..."
  sudo tar -I 'lz4 -1 -c -' -cpf "/etc-$datetime.tar.lz4" /etc/

  find $pathrestore -type f -name "etc*.tar.lz4" -mtime -1 -print0 | \
  while IFS= read -r -d '' file; do
    echo "Restaurando ETC: $file"
    sudo tar -I 'lz4 -d -c -' -xf "$file" -C /etc/
    echo "ETC concluído: $(basename "$file")"
  done

  sudo touch /srv/restored1.lock
  sudo reboot
fi

if ! [ -f /srv/restored2.lock ]
  # 1. Restaurar arquivo qcow2
  cp /backup/pfsense-backup.qcow2 /var/lib/libvirt/images/pfsense.qcow2
  # 2. Redefinir VM
  virsh define pfsense-backup.xml
  # 3. Iniciar VM
  virsh start pfsense
  sudo touch /srv/restored2.lock
  sudo reboot
fi

  #FSTAB: LABEL=sysbkp    /mnt/sysbkp    ext4    defaults,noauto    0 2
