#!/bin/bash

# Tweaks script for Ubuntu Linux
# This script is used to tweak the Ubuntu 24.04 Linux image to make it suitable for the
# Hands-On Fuzzing Workshop without rebuilding an entire new image.

set -euxo pipefail
env

apt-get update
apt-get upgrade -y

# Enable serial console on ttyS1
systemctl enable --now 'getty@ttyS1'

apt-get install -y --no-install-recommends \
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
rm -rf /tmp/casr

bash -c "$(wget -O - https://apt.llvm.org/llvm.sh)"

git clone https://github.com/snort3/libdaq.git /tmp/libdaq \
    && cd /tmp/libdaq \
    && ./bootstrap \
    && ./configure --prefix=/usr \
    && make -j$(nproc) \
    && make install \
    && rm -rf /tmp/libdaq

# Build and install AFLplusplus
git clone https://github.com/AFLplusplus/AFLplusplus /AFLplusplus
cd /AFLplusplus
apt-get install -y build-essential python3-dev automake cmake git flex bison libglib2.0-dev libpixman-1-dev python3-setuptools cargo libgtk-3-dev
# try to install llvm-18 and install the distro default if that fails
apt-get install -y lld-18 llvm-18 llvm-18-dev clang-18 || apt-get install -y lld llvm llvm-dev clang
apt-get install -y gcc-$(gcc --version|head -n1|sed 's/\..*//'|sed 's/.* //')-plugin-dev libstdc++-$(gcc --version|head -n1|sed 's/\..*//'|sed 's/.* //')-dev
apt-get install -y meson ninja-build # for QEMU mode
apt-get install -y wget curl # for Frida mode
apt-get install -y python3-pip # for Unicorn mode
git submodule update --init
make distrib NO_CORESIGHT=1 NO_NYX=1 PERFORMANCE=1
make install NO_CORESIGHT=1 NO_NYX=1 PERFORMANCE=1
afl-system-config
