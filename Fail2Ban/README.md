# Configure

sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

sudo systemctl enable fail2ban && sudo systemctl restart fail2ban

Set custom jail.local, and:

sudo ufw disable && sudo ufw enable 
