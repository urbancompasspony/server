#!/bin/bash

datetime1=$(yq -r '.Informacoes.Data_Instalacao' "$YAML_FILE")
[ "$datetime1" = null ] && {
  datetime0=$(date +"%d/%m/%Y - %H:%M")
  sudo yq -i ".Informacoes.Data_Instalacao = \"${datetime0}\"" /srv/system.yaml
  sudo yq -i ".Informacoes.Data_Restauracao = \"Nunca foi reinstalado.\"" /srv/system.yaml
} || {
  
}

sudo mkdir -p /mnt/bkpsys
sudo mount -t ext4 LABEL=bkpsys /mnt/bkpsys

Restaurar arquivos .yaml para seus devidos lugares.

FSTAB: LABEL=sysbkp    /mnt/sysbkp    ext4    defaults,noauto    0 2

Encontrar todos os containers recentes:
pathrestore=$(find /mnt/bkpsys -name "*.tar.lz4" 2>/dev/null | head -1 | xargs dirname) && echo "Pasta: $path"

sudo mkdir -p /srv/containers

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

# 1. Parar VM se estiver rodando
virsh destroy pfsense
# 2. Remover VM atual
virsh undefine pfsense
# 3. Restaurar arquivo qcow2
cp /backup/pfsense-backup.qcow2 /var/lib/libvirt/images/pfsense.qcow2
# 4. Redefinir VM
virsh define pfsense-backup.xml
# 5. Iniciar VM
virsh start pfsense
