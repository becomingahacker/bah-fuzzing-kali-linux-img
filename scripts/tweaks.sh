#!/bin/bash

# Second-stage (fast) provisioning for the Ubuntu Fuzzing Workshop image.
# Runs on top of the already-built ubuntu-fuzzing-cml-amd64 image produced
# by scripts/setup.sh. Put lesson-material drops and other quick tweaks
# here so full rebuilds from the public Ubuntu family are rare.

set -euxo pipefail
env

flock -w 120 /var/lib/apt/lists/lock -c 'echo waiting for lock'
apt-get update
apt-get upgrade -y

# --- Lesson materials go here ---
# (intentionally empty for now; add curl/git/unzip steps as needed)

echo "tweaks.sh completed at $(date -u +%FT%TZ)" > /etc/ubuntu-fuzzing-tweaks.stamp
