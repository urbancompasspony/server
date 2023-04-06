# Configure

sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

Inside: /etc/fail2ban/paths-common.conf

apache_log = /var/log/apache_fail.log


sudo systemctl enable fail2ban && sudo systemctl restart fail2ban

Set custom jail.local, and:

sudo ufw disable && sudo ufw enable 
