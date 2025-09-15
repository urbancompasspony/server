destiny="/mnt/disk01/bkpsys"
datetime=$(date +"%d_%m_%y")
sudo tar -I 'lz4 -1 -c -' -cpf "$destiny"/etc-"$datetime".tar.lz4 \
    --exclude='/etc/machine-id' \
    /etc/


# 1. Exportar configuração da VM
virsh dumpxml pfsense > pfsense-backup.xml
# 2. Parar a VM (recomendado para consistência)
virsh shutdown pfsense
# 3. Copiar o arquivo qcow2
cp /var/lib/libvirt/images/pfsense.qcow2 /backup/pfsense-backup.qcow2
# 4. Religar a VM
virsh start pfsense

