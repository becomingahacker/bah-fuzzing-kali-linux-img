#!/bin/bash
# Need to run this before we commit + push if we changed these
gcloud storage cp ./rootfs.tar.gz gs://bah-machine-images/payloads/
gcloud storage cp ./fuzzing-workshop-day1-snort.tgz gs://bah-machine-images/payloads/

