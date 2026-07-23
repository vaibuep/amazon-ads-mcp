#!/usr/bin/env bash
# One-time OS-level setup for a fresh Ubuntu VPS (e.g. Oracle Cloud Always
# Free). Installs Docker, opens ports 80/443, and clones this repo.
#
# Usage (on the server, as a user with sudo):
#   curl -fsSL https://raw.githubusercontent.com/vaibuep/amazon-ads-mcp/claude/amazon-ads-mcp-connector-bnxcy2/deploy/setup-server.sh | bash
# or copy the file over and run it directly.
set -euo pipefail

REPO_URL="https://github.com/vaibuep/amazon-ads-mcp.git"
REPO_BRANCH="claude/amazon-ads-mcp-connector-bnxcy2"
REPO_DIR="$HOME/amazon-ads-mcp"

echo "==> Installing Docker Engine + Compose plugin"
if ! command -v docker >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  . /etc/os-release
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER"
  echo "Docker installed. You may need to log out/in for group membership to take effect."
else
  echo "Docker already installed, skipping."
fi

echo "==> Opening firewall ports 80/443 (HTTP/HTTPS)"
if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "Status: active"; then
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
fi
# Oracle Cloud Ubuntu images filter inbound traffic with iptables directly
# (in addition to the VCN security list/NSG configured in the console), and
# ufw is often inactive there. Insert ACCEPT rules ahead of the default
# REJECT so 80/443 pass through the host firewall too.
if command -v iptables >/dev/null 2>&1; then
  for port in 80 443; do
    sudo iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || \
      sudo iptables -I INPUT 1 -p tcp --dport "$port" -j ACCEPT
  done
  if command -v netfilter-persistent >/dev/null 2>&1; then
    sudo netfilter-persistent save
  elif [ -d /etc/iptables ]; then
    sudo sh -c 'iptables-save > /etc/iptables/rules.v4'
  fi
fi
echo "NOTE: If this server is on a cloud provider, also open inbound TCP 80 and 443"
echo "      in its console-level firewall (Oracle: VCN Security List / NSG; AWS: Security Group; etc)."

echo "==> Cloning $REPO_URL ($REPO_BRANCH) into $REPO_DIR"
if [ -d "$REPO_DIR/.git" ]; then
  git -C "$REPO_DIR" fetch origin "$REPO_BRANCH"
  git -C "$REPO_DIR" checkout "$REPO_BRANCH"
  git -C "$REPO_DIR" pull origin "$REPO_BRANCH"
else
  git clone --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
fi

echo ""
echo "==> Done. Next steps:"
echo "  1. cd $REPO_DIR"
echo "  2. cp .env.example .env && edit .env with your credentials (see deploy/DEPLOY.md)"
echo "  3. docker compose -f docker-compose.yaml -f docker-compose.prod.yaml up -d --build"
