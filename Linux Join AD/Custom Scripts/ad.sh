#!/bin/bash

# Change Wallpaper:
gsettings set org.kde.plasma.desktop wallpaper "/mnt/wall.jpg"

WIP
echo "blacklist usb-storage" | sudo tee /etc/modprobe.d/usb-storage.conf
sudo update-initramfs -u
sudo reboot
