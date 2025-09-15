destiny="/mnt/zzz"
datetime=$(date +"%d_%m_%y")

sudo tar -I 'lz4 -1 -c -' -cpf "$destiny"/etc-"$datetime".tar.lz4 \
    --exclude='/etc/machine-id' \
    /etc/
