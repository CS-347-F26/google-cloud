#!/usr/bin/env bash
#
# CS-347 — create one student VM that can host 3-5 Django apps.
#
# Run this from Cloud Shell (nothing to install).  It is idempotent: run it
# again and it will reuse the address / firewall rule it already made.
#
#   ./create-vm.sh stewarmc
#
set -euo pipefail

STUDENT="${1:?usage: ./create-vm.sh <student-id>}"

# Each student owns their own project, so default to whatever gcloud is already
# pointed at rather than hard-coding a class-wide one. Override with
# PROJECT=my-project ./create-vm.sh <id> if you have several.
PROJECT="${PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
: "${PROJECT:?no project set — run: gcloud config set project <your-project-id>}"

REGION="${REGION:-us-central1}"      # free-tier regions: us-central1, us-east1, us-west1
ZONE="${ZONE:-us-central1-c}"
MACHINE="${MACHINE:-e2-micro}"       # e2-micro is the always-free size; e2-small (~$13/mo) if credits allow
VM="cs347-${STUDENT}"

gcloud config set project "$PROJECT"
gcloud services enable compute.googleapis.com

# --- Static IP -------------------------------------------------------------
# Reserve it *before* the VM so the address is stable for the whole semester.
# An ephemeral IP changes every time the VM is stopped and started, which
# would break every bookmark and every ALLOWED_HOSTS entry.
gcloud compute addresses create "${VM}-ip" --region "$REGION" 2>/dev/null || true
IP="$(gcloud compute addresses describe "${VM}-ip" --region "$REGION" --format='value(address)')"

# --- Firewall --------------------------------------------------------------
# Only Caddy is exposed; the apps themselves publish no host ports.
# Port 80 is not optional: Let's Encrypt's HTTP-01 challenge uses it, so
# closing it means certificates never issue and every app fails with a TLS
# error rather than anything that points at the real cause.
gcloud compute firewall-rules create cs347-web \
  --allow=tcp:80,tcp:443 \
  --target-tags=cs347 \
  --description="CS-347 student apps (Caddy)" 2>/dev/null || true

# --- The VM ----------------------------------------------------------------
# --metadata-from-file=startup-script=... is the whole repeatability story:
# the machine configures itself on first boot, so a broken VM is not something
# you debug, it is something you delete and recreate.
gcloud compute instances create "$VM" \
  --zone="$ZONE" \
  --machine-type="$MACHINE" \
  --image-family=debian-13 \
  --image-project=debian-cloud \
  --boot-disk-size=30GB \
  --boot-disk-type=pd-standard \
  --address="$IP" \
  --tags=cs347 \
  --metadata=enable-oslogin=TRUE \
  --metadata-from-file=startup-script=startup-script.sh

cat <<EOF

  VM:   $VM
  IP:   $IP

  NEXT: at your domain registrar, add ONE wildcard A record

      *.yourdomain.dev    A    $IP

  and wait for it to resolve (dig +short library.yourdomain.dev) BEFORE
  starting Caddy. Caddy asks Let's Encrypt for a certificate the first time a
  hostname is requested, and that check fails if DNS is not live yet.

  ssh:  gcloud compute ssh $VM --zone $ZONE

  The startup script takes ~60s after boot to finish installing Docker.
  Watch it with:
    gcloud compute ssh $VM --zone $ZONE --command 'sudo journalctl -u google-startup-scripts -f'

EOF
