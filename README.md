# cc-clip-mac

基于 [cc-clip](https://github.com/ShunmeiCho/cc-clip) 的 macOS 远程主机适配。cc-clip 原生仅支持 Linux 作为远程端，本项目通过 `osascript` shim 使其支持 macOS 远程主机。

## 工作原理

```
本地 Mac (剪贴板)
    │
    ▼
cc-clip daemon (HTTP :18339)
    │
    ▼ SSH RemoteForward
    │
远程 Mac mini (port 18339)
    │
    ▼
osascript shim (拦截剪贴板图片请求)
    │
    ├─ 检测到 PNGf 请求 → 从隧道获取图片 → 写入远程剪贴板
    └─ 其他请求 → 直接透传给 /usr/bin/osascript
```

1. **本地 cc-clip daemon** 读取本机 Mac 剪贴板，通过 HTTP 提供图片数据
2. **SSH RemoteForward** 将本地 18339 端口转发到远程 Mac
3. **osascript shim** 部署在远程 `~/.local/bin/osascript`，优先于系统 `/usr/bin/osascript`
4. 当 Claude Code 调用 `osascript -e 'the clipboard as «class PNGf»'` 读取剪贴板图片时，shim 先从隧道获取本地剪贴板图片并写入远程剪贴板，再执行真正的 osascript

## 前置条件

- 本地和远程均为 macOS
- 本地已安装 [cc-clip](https://github.com/ShunmeiCho/cc-clip)（`curl -fsSL https://raw.githubusercontent.com/ShunmeiCho/cc-clip/main/scripts/install.sh | sh`）
- SSH 可直连远程 Mac（如 `ssh mini`）

## 安装

```bash
cd ~/Claude/cc-clip-mac
./setup-remote-mac.sh mini    # mini 替换为你的 SSH Host 名称
```

脚本会自动完成：
- 检查本地 cc-clip daemon 状态
- 在 `~/.ssh/config` 中为目标 Host 添加 `RemoteForward 18339`
- 部署 osascript shim 和 session token 到远程
- 将 `~/.local/bin` 加入远程 PATH

## 使用

```bash
ssh mini              # 正常 SSH 连接（RemoteForward 自动生效）
claude                # 启动 Claude Code
                      # 在本地 Mac 复制图片，远程 Claude Code 中 Ctrl+V 粘贴
```

## 卸载

```bash
# 删除远程 shim
ssh mini 'rm ~/.local/bin/osascript'

# 删除 SSH 端口转发配置（手动编辑）
# 移除 ~/.ssh/config 中 Host mini 下的 RemoteForward 18339 127.0.0.1:18339

# 停止本地 daemon（可选，如果不再需要 cc-clip）
cc-clip service uninstall
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `setup-remote-mac.sh` | 一键安装脚本 |
| `osascript-shim.sh` | 远程端 osascript 拦截器，部署后位于远程 `~/.local/bin/osascript` |

## 与原版 cc-clip 的区别

| | cc-clip (原版) | cc-clip-mac (本项目) |
|---|---|---|
| 远程系统 | Linux | macOS |
| 拦截目标 | `xclip` shim | `osascript` shim |
| 剪贴板机制 | X11 clipboard | NSPasteboard (AppleScript) |
| Codex 支持 | Xvfb + x11-bridge | 不需要（macOS 有原生剪贴板） |
