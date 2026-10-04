#!/bin/bash
# Dijalankan otomatis sebagai EC2 user-data (Ubuntu 22.04) oleh launch_ec2.sh.
# Memasang dependensi AOSP, Docker, ccache, dan GitHub runner ephemeral (1 job lalu server mati).
set -euxo pipefail
exec > >(tee /var/log/setup_runner.log) 2>&1

: "${GH_REPO:?}" "${RUNNER_TOKEN:?}"
IDLE_MINUTES="${IDLE_MINUTES:-30}"      # mati jika tidak ada job selama N menit
MAX_HOURS="${MAX_HOURS:-10}"            # batas keras umur server (pengaman kredit)
RUNNER_LABELS="${RUNNER_LABELS:-aosp}"
TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"; TG_CHAT_ID="${TG_CHAT_ID:-}"
export DEBIAN_FRONTEND=noninteractive

notify() {
  [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ] || return 0
  curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
    -d chat_id="$TG_CHAT_ID" -d parse_mode=HTML --data-urlencode text="$1" >/dev/null || true
}
notify "🖥 <b>Server AWS menyala</b> ($(hostname)) — menyiapkan runner…"

# ---- Paket ----
apt-get update
apt-get install -y bc bison build-essential ccache curl flex g++-multilib gcc-multilib git git-lfs \
  gnupg gperf imagemagick lib32readline-dev lib32z1-dev libelf-dev liblz4-tool libsdl1.2-dev libssl-dev \
  libxml2 libxml2-utils lzop pngcrush rsync schedtool squashfs-tools xsltproc zip zlib1g-dev python3 \
  openjdk-17-jdk jq unzip docker.io rclone
curl -sL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo
chmod a+rx /usr/local/bin/repo

# ---- Swap 16G (jaga-jaga saat link) ----
if ! swapon --show | grep -q swapfile; then
  fallocate -l 16G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
fi

# ---- User runner ----
id runner >/dev/null 2>&1 || useradd -m -s /bin/bash runner
usermod -aG docker runner
echo "runner ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner
mkdir -p /home/runner/ccache && chown runner:runner /home/runner/ccache

# ---- GitHub runner ----
cd /home/runner && mkdir -p actions-runner && cd actions-runner
VER=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name | sed 's/^v//')
curl -sL "https://github.com/actions/runner/releases/download/v${VER}/actions-runner-linux-x64-${VER}.tar.gz" | tar xz
chown -R runner:runner /home/runner/actions-runner
cat > .env <<ENV
USE_CCACHE=1
CCACHE_EXEC=/usr/bin/ccache
CCACHE_DIR=/home/runner/ccache
LANG=C.UTF-8
ENV
chown runner:runner .env
sudo -u runner ./config.sh --unattended --url "https://github.com/${GH_REPO}" --token "$RUNNER_TOKEN" \
  --labels "$RUNNER_LABELS" --name "aws-$(hostname)" --ephemeral --replace
sudo -u runner ccache -M 50G || true

# ---- Service: 1 job lalu server mati ----
cat > /etc/systemd/system/gh-runner.service <<UNIT
[Unit]
Description=GitHub Actions ephemeral runner
After=network-online.target
[Service]
User=runner
WorkingDirectory=/home/runner/actions-runner
ExecStart=/home/runner/actions-runner/run.sh
Restart=no
ExecStopPost=+/usr/local/bin/aws-shutdown.sh "runner selesai"
[Install]
WantedBy=multi-user.target
UNIT

cat > /usr/local/bin/aws-shutdown.sh <<SH
#!/bin/bash
curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TG_CHAT_ID}" -d parse_mode=HTML \
  --data-urlencode text="🛑 <b>Server AWS dimatikan</b> (\$1)" >/dev/null 2>&1 || true
sleep 5
shutdown -h now
SH
chmod +x /usr/local/bin/aws-shutdown.sh

# ---- Watchdog: idle & batas umur ----
cat > /usr/local/bin/aws-watchdog.sh <<SH
#!/bin/bash
BOOT=\$(date +%s); LAST=\$BOOT
while sleep 60; do
  NOW=\$(date +%s)
  pgrep -f Runner.Worker >/dev/null && LAST=\$NOW
  [ \$((NOW-LAST)) -ge $((IDLE_MINUTES*60)) ] && exec /usr/local/bin/aws-shutdown.sh "idle ${IDLE_MINUTES} menit"
  [ \$((NOW-BOOT)) -ge $((MAX_HOURS*3600)) ] && exec /usr/local/bin/aws-shutdown.sh "batas ${MAX_HOURS} jam"
done
SH
chmod +x /usr/local/bin/aws-watchdog.sh
cat > /etc/systemd/system/aws-watchdog.service <<UNIT
[Unit]
Description=Idle/max-lifetime watchdog
[Service]
ExecStart=/usr/local/bin/aws-watchdog.sh
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now aws-watchdog.service gh-runner.service
notify "✅ <b>Runner AWS siap</b> — jalankan workflow ROM dengan runner <code>self-hosted</code>. Server mati otomatis setelah 1 job atau idle ${IDLE_MINUTES} menit."
