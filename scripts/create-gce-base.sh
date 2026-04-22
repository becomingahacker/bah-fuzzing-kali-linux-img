#!/bin/bash
# Creates GCE base image from ubuntu-minimal-2404-lts-amd64
# Runs in phases with reboots; state is stored in /root/.gce-base-phase.

set -e
set -x
env

# For troubleshooting, disable when not in use.  Serial console only.
echo 'root:CHANGEME' | /usr/sbin/chpasswd

PHASE_FILE=/root/.gce-base-phase
export DEBIAN_FRONTEND=noninteractive
export APT_OPTS="-o Dpkg::Options::=--force-confmiss -o Dpkg::Options::=--force-confnew -o DPkg::Progress-Fancy=0 -o APT::Color=0"

phase() { echo "$1" > "$PHASE_FILE"; }
get_phase() { cat "$PHASE_FILE" 2>/dev/null || echo "0"; }

# Wait (up to ~5 minutes) for any in-progress apt/dpkg activity to release
# the frontend lock.  On first boot, unattended-upgrades and cloud-init's
# package install can both be holding it; without this, concurrent apt-get
# calls here fail with "Could not get lock".
wait_apt_lock() {
  for _ in $(seq 1 60); do
    if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
       && ! fuser /var/lib/dpkg/lock          >/dev/null 2>&1 \
       && ! fuser /var/lib/apt/lists/lock     >/dev/null 2>&1; then
      return 0
    fi
    echo "Waiting for apt/dpkg lock..."
    sleep 5
  done
  echo "Gave up waiting for apt/dpkg lock after 5 minutes" >&2
  return 1
}

case "$(get_phase)" in
  0)
    echo "=== Phase 1: Disable cloud-init network, install generic kernel, fix growroot, grub ==="
    mkdir -p /etc/cloud/cloud.cfg.d
    printf '%s\n' 'network: {config: disabled}' > /etc/cloud/cloud.cfg.d/99_disable_networking_config.cfg
    rm -f /etc/network/interfaces.d/50-cloud-init

    wait_apt_lock
    apt-get update
    # initramfs-tools is not pre-installed on ubuntu-minimal; we need it
    # before we can drop in the growroot hook and run update-initramfs.
    # linux-image-generic pulls it in, but we list both explicitly for
    # clarity and to harden against future base-image changes.  Note the
    # Ubuntu package name is linux-image-generic (Debian uses
    # linux-image-amd64), and we want the generic kernel so the resulting
    # image boots on both GCE (for subsequent Packer builds) and libvirt
    # (CML).
    apt-get install -y initramfs-tools linux-image-generic

    # Fix initramfs growroot (grep/sed/rm/awk in /bin for growpart)
    cat > /usr/share/initramfs-tools/hooks/growroot << 'GROWROOT_EOF'
#!/bin/sh

PREREQ=""

prereqs()
{
        echo "$PREREQ"
}

case $1 in
prereqs)
        prereqs
        exit 0
        ;;
esac

. /usr/share/initramfs-tools/hook-functions

copy_exec /usr/bin/grep /bin
copy_exec /usr/bin/sed /bin
copy_exec /usr/bin/rm /bin
copy_exec /usr/bin/awk /bin

exit 0
GROWROOT_EOF
    chmod u+x /usr/share/initramfs-tools/hooks/growroot
    update-initramfs -u

    # Serial console for GRUB
    echo 'GRUB_TERMINAL_INPUT="serial console"' >> /etc/default/grub
    update-grub

    phase 1
    echo "Phase 1 done. Rebooting..."
    cloud-init clean -c all -r
    ;;
  1)
    echo "=== Phase 2: Remove GCE-specific kernel ==="
    wait_apt_lock
    # On Ubuntu GCE images the pre-installed kernel meta-package is
    # linux-image-gcp (not linux-image-cloud-amd64, which is Debian).
    # Phase 1 has already installed and rebooted into linux-image-generic,
    # so it is safe to purge the gcp-specific kernel and its versioned
    # variants here.
    apt-get remove --purge -y linux-image-gcp || true
    apt-get remove --purge -y 'linux-image-*-gcp' || true
    apt-get autoremove --purge -y || true
    phase 2
    echo "Phase 2 done. Rebooting..."
    cloud-init clean -c all -r
    ;;
  2)
    echo "=== Phase 3: Final cleanup and shutdown ==="
    chsh -s /usr/bin/bash root
    rm -f /etc/hosts /etc/hostname
    cloud-init clean -l --machine-id -c all
    rm -f /root/.zsh_history /root/.bash_history
    history -c 2>/dev/null || true
    phase 3
    echo "Phase 3 done. Shutting down..."
    shutdown -P now
    ;;
  *)
    echo "Already at phase $(get_phase). Exiting."
    exit 0
    ;;
esac
