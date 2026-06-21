#!/usr/bin/env bash
set -Eeuo pipefail

URL="https://raw.githubusercontent.com/torr9522/setup-ai-agent-env/main/setup-ai-agent-env.sh"

if [[ "${EUID}" -ne 0 ]]; then
  echo "请用 root 运行：su - root 后执行，或在有 sudo 的系统执行：sudo bash bootstrap.sh"
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "无法识别系统：缺少 /etc/os-release"
  exit 1
fi

. /etc/os-release
case "${ID:-}:${VERSION_ID:-}" in
  debian:11|debian:12|ubuntu:20.04|ubuntu:22.04|ubuntu:24.04) ;;
  *)
    echo "仅支持 Debian 11/12 与 Ubuntu 20.04/22.04/24.04，当前：${PRETTY_NAME:-unknown}"
    exit 1
    ;;
esac

if ! command -v apt-get >/dev/null 2>&1; then
  echo "未找到 apt-get，无法继续"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  apt-get update
  apt-get install -y curl
fi

if command -v curl >/dev/null 2>&1; then
  bash <(curl -fsSL "$URL")
elif command -v wget >/dev/null 2>&1; then
  bash <(wget -qO- "$URL")
else
  echo "未找到 curl 或 wget，无法下载 setup-ai-agent-env.sh"
  exit 1
fi
