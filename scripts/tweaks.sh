#!/bin/bash

# Second-stage (fast) provisioning for the Ubuntu Fuzzing Workshop image.
# Runs on top of the already-built ubuntu-fuzzing-cml-amd64 image produced
# by scripts/setup.sh. Put lesson-material drops and other quick tweaks
# here so full rebuilds from the public Ubuntu family are rare.

set -euxo pipefail
env

flock -w 120 /var/lib/apt/lists/lock -c 'echo waiting for lock'
apt-get update
apt-get install -y --no-install-recommends iputils-ping # for debugging

# Ubuntu's GCE image pins datasource_list to [GCE, None] via
# /etc/cloud/cloud.cfg.d/90_dpkg.cfg. Under CML (libvirt) we need NoCloud
# (the cidata ISO from cml/node-definition.yaml). Override in a higher-numbered
# drop-in so both environments work.
# TODO: once confirmed working, move this block into scripts/setup.sh and
# trigger a pristine rebuild, then remove from here.
cat > /etc/cloud/cloud.cfg.d/99_workshop-datasources.cfg <<'EOF'
datasource_list: [ NoCloud, ConfigDrive, GCE, None ]
EOF

# Remove the GCE guest agents if an earlier pristine build left them behind.
# This image is built on GCE but deployed on CML/KVM, where there is no
# metadata server, so these services fail at boot and spam the console.
# Safe to re-run: apt-get purge is idempotent and systemctl mask is a no-op
# once the unit files are gone.
# TODO: once confirmed working, this can be dropped from tweaks.sh since
# scripts/setup.sh does the same cleanup on pristine builds.
apt-get purge -y \
    google-guest-agent \
    google-osconfig-agent \
    google-compute-engine \
    google-guest-configs \
    gce-compute-image-packages 2>/dev/null || true
apt-get autoremove --purge -y
systemctl mask \
    google-guest-agent.service \
    google-osconfig-agent.service \
    google-startup-scripts.service \
    google-shutdown-scripts.service \
    gce-workload-cert-refresh.service \
    gce-workload-cert-refresh.timer 2>/dev/null || true

# --- Lesson materials go here ---

# Drop the workshop lesson materials directly into /home/cisco. The tarball
# (uploaded to /provision/lessons.tgz by the packer file provisioner) has
# no top-level wrapper directory, so day1/, day2/, ... land at
# /home/cisco/day1, /home/cisco/day2, etc. Lives in tweaks.sh (not
# setup.sh) so lesson updates ship via fast incremental builds without a
# pristine rebuild. Idempotent: re-running overwrites files in place.
LESSONS_TARBALL=/provision/lessons.tgz
if [ -f "$LESSONS_TARBALL" ]; then
    if ! getent passwd cisco >/dev/null 2>&1; then
        echo "ERROR: cisco user missing; setup.sh must run before tweaks.sh" >&2
        exit 1
    fi
    tar -xzf "$LESSONS_TARBALL" -C /home/cisco
    chown -R cisco:cisco /home/cisco
    rm -f "$LESSONS_TARBALL"
else
    echo "WARNING: $LESSONS_TARBALL not found; skipping lessons extraction" >&2
fi

echo "tweaks.sh completed at $(date -u +%FT%TZ)" > /etc/ubuntu-fuzzing-tweaks.stamp
