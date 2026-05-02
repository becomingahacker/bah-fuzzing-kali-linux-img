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
git clone https://github.com/snort3/snort3.git "$TARGET_DIR/snort3"

SNORT3_REVERT_SHA=73488807aeee7ae738c7d125822366e6c13fcf78
git -C "$TARGET_DIR/snort3" checkout "${SNORT3_REVERT_SHA}^" -- \
    src/network_inspectors/appid/service_plugins/service_bootp.cc \
    src/network_inspectors/appid/service_plugins/test/CMakeLists.txt \
    src/network_inspectors/appid/service_plugins/test/service_plugin_mock.h
git -C "$TARGET_DIR/snort3" rm -f \
    src/network_inspectors/appid/service_plugins/test/service_bootp_test.cc
git -C "$TARGET_DIR/snort3" \
    -c user.name="BAH Fuzzing Workshop" \
    -c user.email="workshop@becomingahacker.invalid" \
    commit -m "workshop: revert bootp OOB fix (${SNORT3_REVERT_SHA:0:12}) for fuzzing exercise"

chown -R cisco:cisco "$TARGET_DIR"

echo "tweaks.sh completed at $(date -u +%FT%TZ)" > /etc/ubuntu-fuzzing-tweaks.stamp
