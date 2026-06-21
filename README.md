# AI Agent Server Bootstrap Script

Debian / Ubuntu 通用的 AI Agent 服务器初始化脚本。

该脚本目标是为 AI Agent 执行环境安装常用基础工具、开发工具、Python/Node/Go/Docker 工具链、浏览器自动化依赖、终端与网络诊断工具，并写入统一环境变量配置。

已在 Debian 11 amd64 上完成实际执行测试：

- 安装检测没有 `[MISS]`
- 未使用 `systemctl start/restart/enable`
- 未安装 `codex/claude/gemini/cline/aider/cursor-agent`
- Docker/containerd 未启动、未启用

## Usage

```bash
sudo bash setup-ai-agent-env.sh
```

执行完成后建议重新登录 SSH，或运行：

```bash
source /etc/profile.d/ai-agent-env.sh
```
