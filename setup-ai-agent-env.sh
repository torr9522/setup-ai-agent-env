#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

if [[ "$EUID" -ne 0 ]]; then
  echo "请用 root 运行：sudo bash $0"
  exit 1
fi

log() {
  echo
  echo "===== $* ====="
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

retry() {
  local n=0
  until "$@"; do
    n=$((n + 1))
    if [[ "$n" -ge 3 ]]; then
      return 1
    fi
    sleep "$((n * 2))"
  done
}

install_apt() {
  apt-get install -y --no-install-recommends "$@"
}

download() {
  local url="$1"
  local out="$2"
  if need_cmd curl; then
    curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$out"
  else
    wget -qO "$out" "$url"
  fi
}

github_latest_asset_url() {
  local repo="$1"
  local pattern="$2"
  curl -fsSL -H "User-Agent: ai-agent-bootstrap" \
    "https://api.github.com/repos/${repo}/releases/latest" \
    | grep '"browser_download_url"' \
    | sed -E 's/.*"([^"]+)".*/\1/' \
    | grep -E "$pattern" \
    | head -n 1
}

cleanup_policy_rcd=0
if [[ -e /usr/sbin/policy-rc.d ]]; then
  cp -a /usr/sbin/policy-rc.d /usr/sbin/policy-rc.d.ai-agent-backup
else
  cleanup_policy_rcd=1
fi

cat > /usr/sbin/policy-rc.d <<'EOF'
#!/usr/bin/env sh
exit 101
EOF
chmod 755 /usr/sbin/policy-rc.d

cleanup() {
  if [[ "$cleanup_policy_rcd" -eq 1 ]]; then
    rm -f /usr/sbin/policy-rc.d
  elif [[ -e /usr/sbin/policy-rc.d.ai-agent-backup ]]; then
    mv -f /usr/sbin/policy-rc.d.ai-agent-backup /usr/sbin/policy-rc.d
  fi
}
trap cleanup EXIT

. /etc/os-release
os_id="${ID:-}"
os_codename="${VERSION_CODENAME:-}"
if [[ -z "$os_codename" && -r /etc/lsb-release ]]; then
  # shellcheck disable=SC1091
  . /etc/lsb-release
  os_codename="${DISTRIB_CODENAME:-}"
fi
if [[ -z "$os_codename" ]] && need_cmd lsb_release; then
  os_codename="$(lsb_release -cs 2>/dev/null || true)"
fi

dpkg_arch="$(dpkg --print-architecture)"
case "$dpkg_arch" in
  amd64) arch="amd64"; go_arch="amd64"; node_arch="x64"; btop_arch="x86_64"; yq_arch="amd64"; ;;
  arm64) arch="arm64"; go_arch="arm64"; node_arch="arm64"; btop_arch="aarch64"; yq_arch="arm64"; ;;
  *) echo "不支持的架构：$dpkg_arch"; exit 1 ;;
esac

if [[ "$os_id" != "debian" && "$os_id" != "ubuntu" ]]; then
  echo "仅支持 Debian / Ubuntu，当前：${PRETTY_NAME:-unknown}"
  exit 1
fi
if [[ -z "$os_codename" ]]; then
  echo "无法识别系统代号，无法配置官方 apt 源"
  exit 1
fi

mkdir -p /etc/apt/keyrings /usr/local/bin /opt /root/bin /root/.local/bin /root/go/bin /root/.cargo/bin
chmod 755 /etc/apt/keyrings
export PATH="/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

log "安装基础 apt 工具"
apt-get update -y
install_apt \
  apt-transport-https ca-certificates curl wget aria2 gnupg lsb-release sudo \
  software-properties-common coreutils findutils procps

log "配置官方 apt 源"
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
cat > /etc/apt/sources.list.d/github-cli.list <<EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main
EOF

curl -fsSL https://download.docker.com/linux/${os_id}/gpg \
  | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${os_id} ${os_codename} stable
EOF

curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
node_major="${NODE_MAJOR:-26}"
cat > /etc/apt/sources.list.d/nodesource.list <<EOF
deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${node_major}.x nodistro main
EOF

if ! apt-get update -y; then
  if [[ "$node_major" != "24" ]]; then
    node_major=24
    cat > /etc/apt/sources.list.d/nodesource.list <<EOF
deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${node_major}.x nodistro main
EOF
    apt-get update -y
  else
    exit 1
  fi
fi

log "安装系统工具与官方 apt 工具"
install_apt \
  sudo curl wget aria2 ca-certificates gnupg \
  git git-lfs gh build-essential make gcc g++ pkg-config \
  python3 python3-pip python3-venv python-is-python3 \
  nodejs \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
  sqlite3 ripgrep fd-find tree plocate jq \
  tmux screen mosh autossh \
  htop iotop ncdu \
  lsof rsync dnsutils net-tools nmap tcpdump iperf3 openssh-client \
  zip unzip gzip bzip2 xz-utils zstd p7zip-full unrar-free tar file \
  bat chromium

git lfs install --system || true
systemctl disable docker.service docker.socket containerd.service >/dev/null 2>&1 || true

log "安装 Python 工具链"
python3 -m pip install --upgrade --break-system-packages pip setuptools wheel pipx || \
  python3 -m pip install --upgrade pip setuptools wheel pipx
ln -sf "$(command -v pip3)" /usr/local/bin/pip || true
ln -sf "$(command -v python3)" /usr/local/bin/python || true
if [[ -x /root/.local/bin/pipx ]] && ! need_cmd pipx; then
  ln -sf /root/.local/bin/pipx /usr/local/bin/pipx
fi
PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install --force uv || true

log "升级 Node 工具链"
npm install -g npm@latest || true
npm install -g pnpm@latest yarn@latest npm-check-updates@latest || true

log "安装最新版 Go"
tmp_dir="$(mktemp -d)"
download 'https://go.dev/dl/?mode=json' "$tmp_dir/go-dl.json"
go_version="$(grep -m1 '"version"' "$tmp_dir/go-dl.json" | sed -E 's/.*"([^"]+)".*/\1/')"
rm -rf "$tmp_dir"
if [[ -n "$go_version" ]]; then
  go_tar="${go_version}.linux-${go_arch}.tar.gz"
  tmp_dir="$(mktemp -d)"
  download "https://go.dev/dl/${go_tar}" "$tmp_dir/go.tar.gz"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "$tmp_dir/go.tar.gz"
  rm -rf "$tmp_dir"
fi

log "安装最新版 yq"
download "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${yq_arch}" /usr/local/bin/yq
chmod 755 /usr/local/bin/yq

log "安装最新版 btop"
if ! need_cmd btop; then
  tmp_dir="$(mktemp -d)"
  download "https://github.com/aristocratos/btop/releases/latest/download/btop-${btop_arch}-unknown-linux-musl.tar.gz" "$tmp_dir/btop.tar.gz"
  tar -xzf "$tmp_dir/btop.tar.gz" -C "$tmp_dir"
  install -m 755 "$tmp_dir/btop/bin/btop" /usr/local/bin/btop
  rm -rf "$tmp_dir"
fi

log "安装最新版 Playwright 与浏览器依赖"
npm install -g playwright@latest || true
npx -y playwright install-deps chromium || true
npx -y playwright install chromium || true

log "创建兼容软链接"
ln -sf "$(command -v python3)" /usr/local/bin/python || true
ln -sf "$(command -v pip3)" /usr/local/bin/pip || true
if need_cmd fdfind; then ln -sf "$(command -v fdfind)" /usr/local/bin/fd; fi
if need_cmd batcat; then ln -sf "$(command -v batcat)" /usr/local/bin/bat; fi
if [[ -x /usr/libexec/docker/cli-plugins/docker-compose ]]; then
  ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
elif [[ -x /usr/lib/docker/cli-plugins/docker-compose ]]; then
  ln -sf /usr/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
fi
if need_cmd chromium; then
  ln -sf "$(command -v chromium)" /usr/local/bin/chromium-browser || true
elif need_cmd chromium-browser; then
  ln -sf "$(command -v chromium-browser)" /usr/local/bin/chromium || true
fi

log "写入环境变量"
cat > /etc/profile.d/ai-agent-env.sh <<'EOF'
export EDITOR=vim
export VISUAL=vim

export PATH="/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

export GOROOT="/usr/local/go"
export GOPATH="$HOME/go"
export GOBIN="$GOPATH/bin"
export PATH="$GOBIN:$PATH"

export CARGO_HOME="$HOME/.cargo"
export PATH="$CARGO_HOME/bin:$PATH"

export PIPX_HOME="${PIPX_HOME:-/opt/pipx}"
export PIPX_BIN_DIR="${PIPX_BIN_DIR:-/usr/local/bin}"
export PATH="$PIPX_BIN_DIR:$PATH"

export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-/usr/local}"
export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"

if command -v chromium >/dev/null 2>&1; then
  export CHROME_BIN="$(command -v chromium)"
  export CHROMIUM_BIN="$(command -v chromium)"
elif command -v chromium-browser >/dev/null 2>&1; then
  export CHROME_BIN="$(command -v chromium-browser)"
  export CHROMIUM_BIN="$(command -v chromium-browser)"
fi

export TERM="${TERM:-xterm-256color}"
EOF
chmod 644 /etc/profile.d/ai-agent-env.sh

if ! grep -q "ai-agent-env.sh" /root/.bashrc 2>/dev/null; then
  cat >> /root/.bashrc <<'EOF'

[ -f /etc/profile.d/ai-agent-env.sh ] && . /etc/profile.d/ai-agent-env.sh
EOF
fi

mkdir -p /root/.ssh
chmod 700 /root/.ssh
cat > /root/.ssh/config <<'EOF'
Host *
  ServerAliveInterval 30
  ServerAliveCountMax 6
  TCPKeepAlive yes
  Compression yes
EOF
chmod 600 /root/.ssh/config

cat > /root/.tmux.conf <<'EOF'
set -g mouse on
set -g history-limit 50000
set -g default-terminal "screen-256color"
EOF

updatedb || true

log "安装检测"
check_cmd() {
  local label="$1"
  shift
  local candidate
  for candidate in "$@"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      echo "[OK] $label"
      return 0
    fi
  done
  echo "[MISS] $label"
}

check_cmd git git
check_cmd gh gh
check_cmd git-lfs git-lfs
check_cmd curl curl
check_cmd wget wget
check_cmd aria2 aria2c
check_cmd python python
check_cmd pip pip
check_cmd pipx pipx
check_cmd uv uv
check_cmd node node
check_cmd npm npm
check_cmd pnpm pnpm
check_cmd yarn yarn
check_cmd go go
check_cmd docker docker
check_cmd docker-compose docker-compose
check_cmd sqlite3 sqlite3
check_cmd rg rg
check_cmd fd fd
check_cmd jq jq
check_cmd yq yq
check_cmd tmux tmux
check_cmd screen screen
check_cmd mosh mosh
check_cmd autossh autossh
check_cmd chromium chromium chromium-browser
check_cmd playwright playwright
check_cmd zip zip
check_cmd unzip unzip
check_cmd 7z 7z
check_cmd zstd zstd
check_cmd rar rar unrar
check_cmd bat bat

echo
echo "完成。建议重新登录 SSH，或执行："
echo "source /etc/profile.d/ai-agent-env.sh"
