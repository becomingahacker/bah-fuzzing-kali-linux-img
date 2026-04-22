# Becoming a Hacker Ubuntu Fuzzing Workshop Image

This Google Cloud Build config builds an Ubuntu 24.04 image for the Offensive 2026 Fuzzing Workshop.

The build uses a two-stage Packer pattern so most builds are fast:

* **`pristine`** – sources the public `ubuntu-minimal-2404-lts-amd64` family and runs
  `scripts/setup.sh` to install the full toolchain (AFL++, casr, libdaq, LLVM, etc.).
  This takes about 25-30 minutes and only needs to be re-run when the base
  toolchain changes.
* **`tweaks`** (default) – sources the already-built `ubuntu-fuzzing-cml-amd64`
  family produced by the pristine build and runs `scripts/tweaks.sh` to layer on
  quick changes such as lesson materials. This completes in a few minutes.

Both stages publish to the same `ubuntu-fuzzing-cml-amd64` image family.

> [!NOTE]
> Creating a pristine image takes about 25-30 minutes. Tweaks builds are
> typically only a few minutes.

## Creating an Ubuntu 24.04 Fuzzing Image

Pick the build mode with the `_BUILD_TYPE` substitution:

* **Tweaks (default, fast)** – edit `scripts/tweaks.sh` (for example, to drop in
  lesson materials), commit, and push. Cloud Build will layer the changes on
  top of the latest `ubuntu-fuzzing-cml-amd64` image.
* **Pristine (slow, rebuild the base)** – edit `scripts/setup.sh`, then trigger
  a build with `_BUILD_TYPE=pristine`, for example:

  ```bash
  gcloud builds submit --substitutions=_BUILD_TYPE=pristine
  ```

  The first time this project is built (before the `ubuntu-fuzzing-cml-amd64`
  family exists), a pristine build must be run to seed the family before any
  tweaks build can succeed.

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