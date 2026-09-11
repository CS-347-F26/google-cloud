#!/usr/bin/env bash
#
# Runs as root on every boot of a CS-347 student VM.
# Must stay idempotent — it re-runs on every restart, not just the first one.
#
set -euxo pipefail

# --- Swap ------------------------------------------------------------------
# e2-micro has 1 GB of RAM. `docker compose build` reliably OOMs without swap,
# and the failure looks like a random "Killed" with no explanation. Do not
# skip this; it is the single most common way this setup appears broken.
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# --- Docker Engine + Compose plugin ---------------------------------------
# From Docker's own repo: Debian's packaged docker.io lags and ships no
# `docker compose` subcommand.
if ! command -v docker >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl git

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io \
                     docker-buildx-plugin docker-compose-plugin
fi

systemctl enable --now docker

# --- Let students run docker without sudo ----------------------------------
# OS Login creates each user's account at their first SSH, which is after this
# script has already run — so we cannot add them to the docker group here.
# This profile.d snippet does it at first login instead. It needs passwordless
# sudo, which roles/compute.osAdminLogin grants. If you only hand out
# roles/compute.osLogin, delete this block and have students type `sudo docker`.
cat > /etc/profile.d/10-cs347-docker.sh <<'EOF'
if ! id -nG "$USER" 2>/dev/null | grep -qw docker; then
  sudo usermod -aG docker "$USER" 2>/dev/null \
    && echo "Added $USER to the docker group — log out and back in once."
fi
EOF
chmod 0644 /etc/profile.d/10-cs347-docker.sh

# --- Workspace -------------------------------------------------------------
install -d -m 0777 /srv/apps
