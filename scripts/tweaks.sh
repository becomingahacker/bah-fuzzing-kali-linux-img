#!/bin/bash

# Tweaks script for Kali Linux
# This script is used to tweak the Kali Linux image to make it suitable for the
# Becoming a Hacker Foundations labs without rebuilding an entire new image.

set -e
set -x
env

flock -w 120 /var/lib/apt/lists/lock -c 'echo waiting for lock'

apt-get update
apt-get upgrade -y

apt remove --purge -y atftpd || true
apt-get install -y tftpd-hpa
cat > /etc/default/tftpd-hpa <<EOF
# /etc/default/tftpd-hpa

TFTP_USERNAME="nobody"
TFTP_DIRECTORY="/srv/tftp"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure --create"

EOF

mkdir -vp /srv/tftp
chown -R nobody:nogroup /srv/tftp

systemctl enable --now tftpd-hpa.service

# Enable serial console on ttyS1
systemctl enable --now 'getty@ttyS1'

apt-get install -y zenmap rdap

userdel -f -r kali || true

apt remove --purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
apt install -y docker.io

rm -rf /provision/websploit || true
mkdir -vp /provision/websploit
cd /provision/websploit
git clone https://github.com/The-Art-of-Hacking/websploit.git
cd websploit
sed -i 's/print_banner/#print_banner/g' install.sh
chmod u+x install.sh
# FIXME cmm - Temporarily disable websploit for troubleshooting
#./install.sh
