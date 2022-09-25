#!/bin/bash

$(cat /home/$USER/.bashrc | grep "menu" 1>/dev/null 2>/dev/null) && {
  echo "alias menu='/home/$USER/.init'" >> /home/$USER/.bashrc
  echo "alias menug='wget https://raw.githubusercontent.com/urbancompasspony/server/main/init -O /home/$USER/.init; chmod +x /home/$USER/.init'" >> /home/$USER/.bashrc
} || {
  echo "Já existe um MENU INIT configurado!"
}

$(cat /home/$USER/.bashrc | grep "menussh" 1>/dev/null 2>/dev/null) && {
  echo "alias menussh='/home/$USER/.ssh'" >> /home/$USER/.bashrc
} || {
  echo "Já existe um MENUSSH configurado!"
}

$(cat /home/$USER/.bashrc | grep "menuvpn" 1>/dev/null 2>/dev/null) && {
  echo "alias menuvpn='/home/$USER/.vpn'" >> /home/$USER/.bashrc
} || {
  echo "Já existe um MENUVPN configurado!"
}

$(cat /home/$USER/.bashrc | grep "orchestration" 1>/dev/null 2>/dev/null) && {
  echo "alias menuorch='curl -sSL https://raw.githubusercontent.com/urbancompasspony/server/main/orchestration | sudo bash'" >> /home/$USER/.bashrc
} || {
  echo "Já existe um Orch configurado!"
}

$(cat /home/$USER/.bashrc | grep "menudocker" 1>/dev/null 2>/dev/null) && {
  echo "alias menudocker='curl -sSL https://raw.githubusercontent.com/urbancompasspony/server/main/docker | sudo bash'" >> /home/$USER/.bashrc
} || {
  echo "Já existe um MENUDOCKER configurado!"
}

. .bashrc

exit 0
