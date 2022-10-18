# Universal Server Menu

The default code is "srv" and the main is "init", that is mentioned below.
The "live" and "live-root" versions has less resources and is used when booting only in LIVE USBs.

# What is it?

For now only in Brazillian Portuguese!

A code to run a customizable menu based 100% on Shell Script and created over DIALOG.
It will let you configure your linux server in no time!

Some options are adjust Active Directory & Domain Controller over Linux, like creating, removing, blocking or changing passwords for users and etc; check status of lots of services like apache2, samba, DRBD and etc; create reports and sent them over e-mail; using tools like arp-scan or traceroute easyly; and much more.

# Where to run it

Debian-based Linux machines!
Can't tell if it works on other linux like Manjaro, Fedora or even CentOS with yum, dnf or pkg based packages.
I can tell that works on Ubuntu, Debian, LinuxMint, Zorin and more.

# How to run it

Just type this on your terminal:

## curl -sSL https://srv.linuxuniverse.com.br | bash

When running for the first time it will install some dependencies, they are:
dialog, lm-sensors, whois, arp-scan, traceroute, libatasmart-bin, mutt, udpcast

After install, you will be prompted for your SUDO password to access the administrator functionalities.

# MENU

The main menu starts with a prompt for password.
You can put your sudo password, to enable administrator tools and resources, but with a Secret Password you can access the secret menu!
After putting password, you will be prompted to enable or not the report over e-mail.

# New Docker Menu and Orchestration

Used to controll some containers made with Docker
