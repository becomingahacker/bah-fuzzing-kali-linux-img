packer {
  required_plugins {
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = "~> 1"
    }
  }
}

variable "project_id" {
    type        = string
    default     = ""
    description = "Project ID, e.g. gcp-asigbahgcp-nprd-47930"
}

variable "zone" {
    type        = string
    default     = ""
    description = "Zone, e.g. us-east1-b."
}

variable "service_account_email" {
    type        = string
    default     = ""
    description = "Service account to use while building."
}

variable "source_image_family" {
    type        = string
    default     = "ubuntu-minimal-2404-lts-amd64"
    description = "Parent image family, e.g. ubuntu-minimal-2404-lts-amd64"
}

variable "provision_script" {
    type        = string
    default     = "setup.sh"
    description = "Provisioning script"
}

variable "output_image_family" {
    type        = string
    default     = "ubuntu-fuzzing-cml-amd64"
    description = "Output image family name"
}

variable "output_image_name_prefix" {
    type        = string
    default     = "ubuntu-fuzzing"
    description = "Output image name prefix"
}

locals {
  ssh_public_key          = file("${path.root}/secrets/id_ed25519.pub")

  user_data = {
    users = [
      {
        name                = "root"
        lock_passwd         = true
        ssh_authorized_keys = [
          local.ssh_public_key,
        ]
      },
    ]
  }
}

source "googlecompute" "fuzzing-workshop-image" {
  project_id              = var.project_id
  source_image_family     = var.source_image_family
  image_family            = var.output_image_family
  image_name              = "${var.output_image_name_prefix}-{{timestamp}}"

  zone                    = var.zone
  machine_type            = "n2-highcpu-8"

  disk_size               = 48
  disk_type               = "pd-ssd"
  image_storage_locations = [
    "us-east1",
  ]

  use_iap = true # Use IAP role
  ssh_username            = "root"
  ssh_private_key_file    = "secrets/id_ed25519"
  service_account_email   = var.service_account_email

  scopes = [
    "https://www.googleapis.com/auth/cloud-platform",
  ]

  metadata = {
    user-data = format("#cloud-config\n%s", yamlencode(local.user_data))
  }
}

build {
  sources = ["sources.googlecompute.fuzzing-workshop-image"]

  provisioner "shell" {
    inline = [
      "mkdir -p /provision"
    ]
  }

  # These are files copied here, rather than in the cloud-init because we don't
  # want to do any YAML encoding/processing on them.
  provisioner "file" {
    source      = "/workspace/scripts/setup.sh"
    destination = "/provision/"
  }

  provisioner "file" {
    source      = "/workspace/scripts/tweaks.sh"
    destination = "/provision/"
  }

  # Workshop rootfs payload. Extracted by setup.sh into /opt/rootfs and
  # exposed via the ROOT env var. ~864 MB compressed; only needed for
  # pristine builds (setup.sh), but uploading it unconditionally keeps
  # the packer config simple and tweaks builds skip it via the file
  # check in setup.sh.
  provisioner "file" {
    source      = "/workspace/rootfs.tar.gz"
    destination = "/provision/rootfs.tar.gz"
  }

  # Let cloud-init finish before running the
  # main provisioning script.  If cloud-init fails,
  # output the log and stop the build.
  provisioner "shell" {
    inline = [ <<-EOF
      echo "waiting for cloud-init setup to finish..."
      cloud-init status --wait || true

      cloud_init_state="$(cloud-init status | awk '/status:/ { print $2 }')"

      if [ "$cloud_init_state" = "done" ]; then
        echo "cloud-init setup has successfully finished"
      else
        echo "cloud-init setup is in unknown state: $cloud_init_state"
        cloud-init status --long
        cat /var/log/cloud-init-output.log
        echo "stopping build..."
        exit 1
      fi
      
      echo "Starting main provisioning script..."
      chmod u+x /provision/${var.provision_script}
      /provision/${var.provision_script}

      # On pristine builds, also run tweaks.sh so the published pristine
      # image already has the second-stage lesson tweaks (and any cloud-init
      # / CML overrides currently living in tweaks.sh) applied.  This means
      # an image freshly produced from a pristine build is deployable on CML
      # without first running a follow-up tweaks build.
      if [ "${var.provision_script}" = "setup.sh" ]; then
        echo "Pristine build: chaining tweaks.sh after setup.sh..."
        chmod u+x /provision/tweaks.sh
        /provision/tweaks.sh
      fi
    EOF
    ]
    env = { 
      APT_OPTS         = "-o Dpkg::Options::=--force-confmiss -o Dpkg::Options::=--force-confnew -o DPkg::Progress-Fancy=0 -o APT::Color=0"
      DEBIAN_FRONTEND  = "noninteractive"
    }
  }

  # Reclaim space so the exported qcow2 is sparse.  This shrinks the qcow2
  # artifact and the time `gcloud compute images export` spends reading,
  # converting, and uploading it.  On pd-ssd + ext4, `fstrim` unmaps free
  # blocks and `qemu-img convert` treats them as holes, so we don't need a
  # separate zero-fill pass on incremental (tweaks) builds.  We do run a
  # zero-fill on pristine builds, where the underlying base image may have
  # non-zero garbage in previously-used blocks.
  provisioner "shell" {
    inline = [ <<-EOF
      set -e

      apt-get clean || true
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb || true

      journalctl --rotate || true
      journalctl --vacuum-time=1s || true

      rm -rf /tmp/* /var/tmp/* /root/.cache || true
      find /home -maxdepth 2 -type d -name .cache -exec rm -rf {} + || true

      fstrim -av || true

      if [ "${var.provision_script}" = "setup.sh" ]; then
        echo "pristine build: zero-filling free space for a clean baseline"
        rm -f /var/tmp/ZERO
      fi

      sync
    EOF
    ]
  }

  # Clean up all cloud-init data and shutdown cleanly.
  provisioner "shell" {
    inline = [
      "cloud-init clean -c all -l --machine-id",
      "rm -rf /var/lib/cloud",
      "sync",
      "sync",
    ]
  }

  post-processor "manifest" {
    output = "/workspace/manifest.json"
    strip_path = true
    #custom_data = {
    #  foo = "bar"
    #}
  }
}
