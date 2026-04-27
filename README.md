# Becoming a Hacker Ubuntu Fuzzing Workshop Image

This Google Cloud Build config builds an Ubuntu 24.04 image for the Offensive 2026 Fuzzing Workshop.

The pipeline has three tiers; each feeds the next as an image family and each is
re-run at its own cadence:

* **Base** (`cloudbuild-base.yaml`) – takes the public
  `ubuntu-minimal-2404-lts-amd64` family and runs the phased
  `scripts/create-gce-base.sh` to convert it into a libvirt-friendly image
  (generic kernel, NoCloud/ConfigDrive-friendly cloud-init, growroot initramfs
  hook). Published to the `ubuntu-fuzzing-base-cml-amd64` family. Rarely
  re-run – only when the underlying Ubuntu LTS needs refreshing or the base
  family needs to be re-seeded (e.g. in a new project).
* **Pristine** (`cloudbuild.yaml` with `_BUILD_TYPE=pristine`) – sources the
  `ubuntu-fuzzing-base-cml-amd64` family, runs `scripts/setup.sh` to install
  the full toolchain (AFL++, casr, libdaq, LLVM, etc.), and then chains
  `scripts/tweaks.sh` at the end so the published image is immediately
  deployable on CML (no follow-up tweaks build required). Takes about
  25-30 minutes; only needs to be re-run when the base toolchain changes.
* **Tweaks** (`cloudbuild.yaml`, default) – sources the already-built
  `ubuntu-fuzzing-cml-amd64` family produced by the pristine build and runs
  `scripts/tweaks.sh` to layer on quick changes such as lesson materials.
  Completes in a few minutes.

Both pristine and tweaks stages publish to the same `ubuntu-fuzzing-cml-amd64`
image family.

> [!NOTE]
> Creating a pristine image takes about 25-30 minutes. Tweaks builds are
> typically only a few minutes.

## Creating an Ubuntu 24.04 Fuzzing Image

Pick the build mode with the `_BUILD_TYPE` substitution:

* **Tweaks (default, fast)** – edit `scripts/tweaks.sh` (for example, to drop in
  lesson materials), commit, and push. Cloud Build will layer the changes on
  top of the latest `ubuntu-fuzzing-cml-amd64` image.
* **Pristine (slow, rebuild the toolchain)** – edit `scripts/setup.sh`, then trigger
  a build with `_BUILD_TYPE=pristine`, for example:

  ```bash
  gcloud builds submit --substitutions=_BUILD_TYPE=pristine
  ```

  The first time this project is built (before the `ubuntu-fuzzing-cml-amd64`
  family exists), a pristine build must be run to seed the family before any
  tweaks build can succeed.

### Seeding or refreshing the base image family

Before the first pristine build can run in a new project (or after the base
needs refreshing), the `ubuntu-fuzzing-base-cml-amd64` family must exist. It
is produced by a separate Cloud Build config which drives
`scripts/create-gce-base.sh`:

```bash
gcloud builds submit --config=cloudbuild-base.yaml
```

This spins up a short-lived GCE VM from the public
`ubuntu-minimal-2404-lts-amd64` family, runs the phased preparation script
(two reboots + a final shutdown), snapshots the disk into the
`ubuntu-fuzzing-base-cml-amd64` family, and cleans up the VM. Takes roughly
10-15 minutes and only needs to be repeated when the Ubuntu LTS or base
preparation changes.

## Troubleshooting

### Replacing the Image in CML

* If you want to replace the Ubuntu Fuzzing image with a new one, you must
  **STOP**, **WIPE**, **DELETE** all pods, then log into the CML controller
  and restart the `virl2.target` systemd unit after the image is built.

E.g.  To delete the pods, from the `bah-fuzzing-lab` repository:

```
tofu destroy -target module.pod
```

This will destroy the pods, and **leave the users, passwords and groups alone**.

```bash
gcloud compute ssh cml-controller  --project=gcp-asigbahgcp-nprd-47930 --zone=us-east1-b --tunnel-through-iap --ssh-flag='-p 1122'
sudo -i
./refresh.sh
```