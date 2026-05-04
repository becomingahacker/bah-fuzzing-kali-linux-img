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

TARGET_DIR=/home/cisco/target
install -d -o cisco -g cisco "$TARGET_DIR"
rm -rf "$TARGET_DIR/libdaq" "$TARGET_DIR/snort3"
git clone https://github.com/snort3/libdaq.git "$TARGET_DIR/libdaq"

# Snort3 fuzzing target: clone upstream snort3, then revert just the
# bootp service plugin to its pre-fix state so the OOB read introduced in
# https://github.com/snort3/snort3/commit/73488807aeee7ae738c7d125822366e6c13fcf78
# is exploitable by the day-1 lesson harness. We need full git history
# (no --depth=1) so we can `git checkout <commit>^ -- <file>` to grab the
# parent revision of just service_bootp.cc.
SNORT_FIX_COMMIT=73488807aeee7ae738c7d125822366e6c13fcf78
SNORT_BOOTP_PATH=src/network_inspectors/appid/service_plugins/service_bootp.cc

git clone https://github.com/snort3/snort3.git "$TARGET_DIR/snort3"
git -C "$TARGET_DIR/snort3" checkout "${SNORT_FIX_COMMIT}^" -- "$SNORT_BOOTP_PATH"

# Drop the day-1 fuzzing harness (provided by the lessons repo) into the
# snort3 source tree at the locations the lesson and CMake expects:
#   - service_plugins/fuzz/  : libFuzzer harnesses, mocks, CMakeLists.txt
#   - fuzz/scripts/compile/  : AFL++ build helper
#   - fuzz/seed/bootp_seeds/ : seed corpus for bootp harness
LESSON_DAY1=$LESSONS_TMP/docs/day-1
APPID_FUZZ_DIR=$TARGET_DIR/snort3/src/network_inspectors/appid/service_plugins/fuzz
FUZZ_COMPILE_DIR=$TARGET_DIR/snort3/fuzz/scripts/compile
FUZZ_SEED_DIR=$TARGET_DIR/snort3/fuzz/seed

install -d "$APPID_FUZZ_DIR" "$FUZZ_COMPILE_DIR" "$FUZZ_SEED_DIR"
# Intentionally exclude the *-answer.cc files: students complete the
# bootp-fuzz-template.cc and service_plugin_mock.cc skeletons themselves
# during the day-1 lesson. Answer files remain available under
# /home/cisco/guides/day-1 for instructors / post-lesson review.
cp -a \
    "$LESSON_DAY1/CMakeLists.txt" \
    "$LESSON_DAY1/bootp-fuzz-template.cc" \
    "$LESSON_DAY1/service_plugin_mock.cc" \
    "$APPID_FUZZ_DIR/"
# Scrub any pre-existing answer files in case an older
# tweaks build (or a future cp regression) left them in the fuzz dir.
rm -f \
    "$APPID_FUZZ_DIR/bootp-fuzz-template-answer.cc" \
    "$APPID_FUZZ_DIR/new_service_plugin_mock-answer.cc" || true
cp -a "$LESSON_DAY1/build-afl-fuzzers.sh" "$FUZZ_COMPILE_DIR/"
chmod +x "$FUZZ_COMPILE_DIR/build-afl-fuzzers.sh"
cp -a "$LESSON_DAY1/bootp_seeds" "$FUZZ_SEED_DIR/"

# Wire the new fuzz subdirectory into the appid build, gated on the same
# ENABLE_FUZZERS option Snort already uses for its in-tree fuzz targets.
# Equivalent to:  239a240,242
#                 > if(ENABLE_FUZZERS)
#                 >     add_subdirectory (service_plugins/fuzz)
#                 > endif(ENABLE_FUZZERS)
# Idempotent: skipped if the subdir is already wired in.
APPID_CMAKE=$TARGET_DIR/snort3/src/network_inspectors/appid/CMakeLists.txt
if ! grep -qF 'service_plugins/fuzz' "$APPID_CMAKE"; then
    awk 'NR==239 {
        print
        print "if(ENABLE_FUZZERS)"
        print "    add_subdirectory (service_plugins/fuzz)"
        print "endif(ENABLE_FUZZERS)"
        next
    } { print }' "$APPID_CMAKE" > "$APPID_CMAKE.new"
    mv "$APPID_CMAKE.new" "$APPID_CMAKE"
fi

rm -rf "$LESSONS_TMP"

chown -R cisco:cisco "$TARGET_DIR"

echo "tweaks.sh completed at $(date -u +%FT%TZ)" > /etc/ubuntu-fuzzing-tweaks.stamp
