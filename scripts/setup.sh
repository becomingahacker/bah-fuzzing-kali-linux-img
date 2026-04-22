#!/bin/bash

# Tweaks script for Ubuntu Linux
# This script is used to tweak the Ubuntu 24.04 Linux image to make it suitable for the
# Hands-On Fuzzing Workshop.

set -euxo pipefail
env

flock -w 120 /var/lib/apt/lists/lock -c 'echo waiting for lock'
apt update
apt upgrade -y
printf "LANG=en_US.UTF-8\nLC_ALL=en_US.UTF-8\n" > /etc/default/locale
apt install -y --no-install-recommends locales sudo
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

apt install -y --no-install-recommends \
    build-essential \
    clang \
    llvm \
    llvm-dev \
    git \
    curl \
    ca-certificates \
    autoconf \
    automake \
    build-essential \
    clangd \
    cmake \
    curl \
    flex \
    git \
    git-lfs \
    gnupg \
    libdumbnet-dev \
    libhwloc-dev \
    liblua5.3-dev \
    libluajit-5.1-dev \
    liblzma-dev \
    libpcap-dev \
    libpcre2-dev \
    libpcre3-dev \
    libssl-dev \
    libtool \
    lsb-release \
    lua5.3 \
    make \
    nano \
    patchelf \
    pkg-config \
    python3.12-venv \
    software-properties-common \
    wget \
    zip \
    zlib1g \
    zlib1g-dev

# Install Rust for casr
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source $HOME/.cargo/env
git clone https://github.com/ispras/casr.git /tmp/casr
cd /tmp/casr
cargo update && cargo build --release && cp -r target/release/* /usr/local/bin/
cd / && rm -rf /tmp/casr

bash -c "$(wget -O - https://apt.llvm.org/llvm.sh)"

git clone https://github.com/snort3/libdaq.git /tmp/libdaq \
    && cd /tmp/libdaq \
    && ./bootstrap \
    && ./configure --prefix=/usr \
    && make -j$(nproc) \
    && make install \
    && cd / \
    && rm -rf /tmp/libdaq

# Build and install AFLplusplus
git clone https://github.com/AFLplusplus/AFLplusplus /AFLplusplus
cd /AFLplusplus
apt install -y build-essential python3-dev automake cmake git flex bison libglib2.0-dev libpixman-1-dev python3-setuptools cargo libgtk-3-dev
# try to install llvm-18 and install the distro default if that fails
apt install -y lld-18 llvm-18 llvm-18-dev clang-18 || apt-get install -y lld llvm llvm-dev clang
apt install -y gcc-$(gcc --version|head -n1|sed 's/\..*//'|sed 's/.* //')-plugin-dev libstdc++-$(gcc --version|head -n1|sed 's/\..*//'|sed 's/.* //')-dev
apt install -y meson ninja-build # for QEMU mode
apt install -y wget curl # for Frida mode
apt install -y python3-pip # for Unicorn mode
git submodule update --init
make distrib NO_CORESIGHT=1 NO_NYX=1 PERFORMANCE=1
make install NO_CORESIGHT=1 NO_NYX=1 PERFORMANCE=1
afl-system-config
cd /

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

# This image is built on GCE (from the ubuntu-minimal-2404-lts-amd64 family)
# but deployed on CML/KVM, where there is no GCE metadata server at
# 169.254.169.254. Without this, google-guest-agent, google-osconfig-agent,
# and google-{startup,shutdown}-scripts all fail at boot and spam the console.
# Do this near the end of provisioning so Packer's own SSH session (which uses
# a cloud-init-injected key, not the guest agent) isn't disturbed.
apt-get purge -y \
    google-guest-agent \
    google-osconfig-agent \
    google-compute-engine \
    google-guest-configs \
    gce-compute-image-packages 2>/dev/null || true
apt-get autoremove --purge -y
# Defense in depth: if any stragglers remain (e.g. reintroduced by a future
# apt upgrade), mask their units so systemd won't attempt to start them.
systemctl mask \
    google-guest-agent.service \
    google-osconfig-agent.service \
    google-startup-scripts.service \
    google-shutdown-scripts.service 2>/dev/null || true

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
