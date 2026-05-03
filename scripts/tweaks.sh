#!/bin/bash

# Second-stage (fast) provisioning for the Ubuntu Fuzzing Workshop image.
# Runs on top of the already-built ubuntu-fuzzing-cml-amd64 image produced
# by scripts/setup.sh. Put lesson-material drops and other quick tweaks
# here so full rebuilds from the public Ubuntu family are rare.

set -euxo pipefail
env

flock -w 120 /var/lib/apt/lists/lock -c 'echo waiting for lock'
apt-get update
apt-get install -y --no-install-recommends iputils-ping mtr # for debugging

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

# Drop the workshop guides into /home/cisco/guides by shallow-cloning only the
# `docs` branch of bah-fuzzing-lab and copying the relevant subtree. Lives in
# tweaks.sh (not setup.sh) so lesson updates ship via fast incremental builds
# without a pristine rebuild. Idempotent: re-running refreshes files in place.
if ! getent passwd cisco >/dev/null 2>&1; then
    echo "ERROR: cisco user missing; setup.sh must run before tweaks.sh" >&2
    exit 1
fi

LESSONS_REPO_URL=https://github.com/becomingahacker/bah-fuzzing-lab.git
LESSONS_TMP=/tmp/bah-fuzzing-lab
GUIDES_DIR=/home/cisco/guides

rm -rf "$LESSONS_TMP"
git clone --depth 1 --branch docs --single-branch "$LESSONS_REPO_URL" "$LESSONS_TMP"

install -d -o cisco -g cisco "$GUIDES_DIR"
cp -a \
    "$LESSONS_TMP/docs/day-1" \
    "$LESSONS_TMP/docs/day-2" \
    "$LESSONS_TMP/docs/parking_game" \
    "$LESSONS_TMP/docs/index.md" \
    "$GUIDES_DIR/"
chown -R cisco:cisco "$GUIDES_DIR"
rm -rf "$LESSONS_TMP"

TARGET_DIR=/home/cisco/target
install -d -o cisco -g cisco "$TARGET_DIR"
rm -rf "$TARGET_DIR/libdaq" "$TARGET_DIR/snort3"
git clone https://github.com/snort3/libdaq.git "$TARGET_DIR/libdaq"

# Snort3 fuzzing target is shipped out-of-band as a tarball staged into
# /provision/ by the packer file provisioner (sourced from
# ${GS_PAYLOADS_PATH}/fuzzing-workshop-day1-snort.tgz in cloudbuild.yaml).
# Replaces the previous `git clone` of bryhuang_cisco/fuzzing-workshop-day1-snort
# so lesson updates can ship without depending on that private repo. The
# tarball has a single top-level fuzzing-workshop-day1-snort/ directory;
# strip it so contents land directly in /home/cisco/target/snort3.
SNORT_TARBALL=/provision/fuzzing-workshop-day1-snort.tgz
if [ ! -f "$SNORT_TARBALL" ]; then
    echo "ERROR: $SNORT_TARBALL not found; cloudbuild.yaml must stage it from GCS" >&2
    exit 1
fi
install -d -o cisco -g cisco "$TARGET_DIR/snort3"
tar -xzf "$SNORT_TARBALL" -C "$TARGET_DIR/snort3" --strip-components=1
rm -f "$SNORT_TARBALL"

chown -R cisco:cisco "$TARGET_DIR"

echo "tweaks.sh completed at $(date -u +%FT%TZ)" > /etc/ubuntu-fuzzing-tweaks.stamp
