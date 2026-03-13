# Becoming a Hacker Ubuntu Fuzzing Workshop Image

This Google Cloud Build config builds an Ubuntu 24.04 image for the Offensive 2026 Fuzzing Workshop.

> [!NOTE]
> Creating a pristine image takes about 25-30 minutes.

## Creating an Ubuntu 24.04 Fuzzing Image

* Edit `scripts/setup.sh` with your desired changes. It will be run by Packer.
* Commit and push this repository and cloud-build will run.

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

```
gcloud compute ssh cml-controller --tunnel-through-iap --plain --ssh-flag='-p1122'
sudo -i

journalctl -f &
systemctl stop virl2.target
systemctl start virl2.target
```