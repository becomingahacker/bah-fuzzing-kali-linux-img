#!/bin/bash

# Setup script for Ubuntu 24.04 Linux
# This script is used to setup the Ubuntu 24.04 Linux image to make it suitable for the
# Hands-On Fuzzing Workshop and building a new pristine image.

set -euxo pipefail
env

# Wait for possible auto updates to complete.  This may not be needed
flock -w 120 /var/lib/apt/lists/lock -c 'echo waiting for lock'

apt-get update
apt-get upgrade -y

# Set the locale to en_US.UTF-8
printf "LANG=en_US.UTF-8\nLC_ALL=en_US.UTF-8\n" > /etc/default/locale
apt-get install -y locales sudo
locale-gen --purge "en_US.UTF-8"
dpkg-reconfigure locales

# Set the timezone to Eastern
timedatectl set-timezone America/New_York

# Enable serial console on ttyS1
systemctl enable --now 'getty@ttyS1'

# Make network timeout shorter to speed up boot if the network is unavailable
mkdir -p /etc/systemd/system/networking.service.d/
echo -e \"[Service]\nTimeoutStartSec=60sec\" > /etc/systemd/system/networking.service.d/timeout.conf

# Don't display message when automatically logging in
touch /root/.hushlogin

# Ensure cisco user exists with a proper home directory so X/lightdm and
# gnome-keyring can write .Xauthority and ~/.local/share/keyrings.
if ! getent passwd cisco >/dev/null 2>&1; then
  useradd -m -s /bin/bash -G users,adm,sudo cisco
fi
if [ -d /home/cisco ]; then
  chown -R cisco:cisco /home/cisco
  chmod 755 /home/cisco
fi
# Lock until deploy-time cloud-init sets password (e.g. CML node-definition)
passwd -l cisco 2>/dev/null || true

# Clean up after ourselves
cat > /etc/cloud/clean.d/10-cml-clean <<EOF
#!/bin/sh -x

sudo rm /etc/hosts
sudo rm /etc/hostname

sudo rm /root/.zsh_history
sudo rm /root/.bash_history
sudo truncate -s 0 /root/.ssh/authorized_keys

# Clean up packages that can be removed
apt-get autoremove --purge -y
apt-get clean

EOF
chmod u+x /etc/cloud/clean.d/10-cml-clean
