#!/bin/bash

sudo mkdir -p /srv/containers
sudo mkdir -p /mnt/bkpsys
sudo mount -t ext4 LABEL=bkpsys /mnt/bkpsys

pathrestore=$(find /mnt/bkpsys -name "*.tar.lz4" 2>/dev/null | head -1 | xargs dirname)

docker network create -d macvlan \
  --subnet=$(jq -r '.[0].IPAM.Config[0].Subnet' backup-macvlan.json) \
  --gateway=$(jq -r '.[0].IPAM.Config[0].Gateway' backup-macvlan.json) \
  -o parent=$(jq -r '.[0].Options.parent' backup-macvlan.json) \
  $(jq -r '.[0].Name' backup-macvlan.json)

if ! [ -f /srv/restored0.lock ]; then
  cp "$destiny"/fstab-"$datetime".backup /tmp/fstab.backup

  file="$1"
  echo "1. Restaurando /etc completo (exceto fstab)..."
  sudo tar -I 'lz4 -d -c' -xpf "$file" --exclude='etc/fstab' -C /
  echo "2. Aplicando merge do fstab..."
  sudo cp /etc/fstab /etc/fstab.before_merge.$(date +%Y%m%d_%H%M%S)
  sudo tar -I 'lz4 -d -c' -xpf "$file" etc/fstab -O > /tmp/fstab.backup
  awk '
FNR==NR { seen[$2]++; next }
!seen[$2] { print }
' /etc/fstab /tmp/fstab.backup | sudo tee -a /etc/fstab
  echo "3. Testando configuração..."
  sudo mount -a --fake && echo "✓ fstab válido" || echo "✗ Erro no fstab!"
  rm /tmp/fstab.backup
  echo "Restore completo!"
  sudo touch /srv/restored0.lock  
fi

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
    #sudo tar -I 'lz4 -d -c -' -xf "$file" --exclude='etc/fstab' -C /etc/
    sudo tar -I 'lz4 -d -c' -xpf "$file" --exclude='etc/fstab' -C /
    echo "ETC concluído: $(basename "$file")"
  done

# Extrair fstab do backup para um local temporário
sudo tar -I 'lz4 -d -c' -xpf "$file" etc/fstab -O > /tmp/fstab.backup
# Fazer backup do fstab atual por segurança
sudo cp /etc/fstab /etc/fstab.before_merge.$(date +%Y%m%d_%H%M%S)
# Aplicar o merge inteligente
awk '
FNR==NR { seen[$2]++; next }
!seen[$2] { print }
' /etc/fstab /tmp/fstab.backup | sudo tee -a /etc/fstab
# Limpar arquivo temporário
rm /tmp/fstab.backup

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
