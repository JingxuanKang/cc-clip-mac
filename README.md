# cc-clip-mac

通过 SSH 连接远程 Mac 使用 Claude Code 时，将本地 Mac 剪贴板的图片无缝粘贴到远程 Claude Code 中。

## 解决什么问题

SSH 到远程 Mac 后，在 Claude Code 中按 Ctrl+V 粘贴图片时，读取的是远程 Mac 的剪贴板，而不是你本地 Mac 的。本工具让你在本地复制的图片可以直接粘贴到远程 Claude Code 中，体验和本地一样。

## 工作原理

```
本地 Mac (剪贴板)
    │
    ▼
clipboard daemon (HTTP :18339, 读取本地剪贴板提供图片)
    │
    ▼ SSH RemoteForward (自动端口转发)
    │
远程 Mac (port 18339)
    │
    ▼
osascript shim (拦截 Claude Code 的剪贴板图片请求)
    │
    ├─ 检测到图片请求 → 从隧道获取本地图片 → 写入远程剪贴板 → 执行原始请求
    └─ 其他请求 → 直接透传给 /usr/bin/osascript
```

Claude Code 在 macOS 上通过 `osascript -e 'the clipboard as «class PNGf»'` 读取剪贴板图片。本工具在远程 Mac 的 `~/.local/bin/` 放置一个 `osascript` shim，优先于系统的 `/usr/bin/osascript`。当检测到剪贴板图片请求时，shim 先通过 SSH 隧道从本地 Mac 获取图片并写入远程剪贴板，然后正常执行 osascript。非剪贴板请求完全透传，不影响任何其他功能。

## 前置条件

- **本地**：macOS 13+，[Go 1.25+](https://go.dev/dl/)，[Homebrew](https://brew.sh)
- **远程**：macOS，已在 `~/.ssh/config` 中配置 Host

## 安装

```bash
git clone https://github.com/JingxuanKang/cc-clip-mac.git
cd cc-clip-mac
./install.sh <ssh-host>
```

例如，SSH Host 名为 `mini`：

```bash
git clone https://github.com/JingxuanKang/cc-clip-mac.git
cd cc-clip-mac
./install.sh mini
```

安装脚本会自动完成：

1. 从源码编译并安装本地剪贴板服务，安装 pngpaste
2. 启动本地剪贴板 HTTP 服务
3. 在 `~/.ssh/config` 中添加 `RemoteForward 18339`
4. 验证 SSH 连接并确认远程是 macOS
5. 部署 osascript shim 和认证 token 到远程
6. 端到端验证

## 使用

```bash
ssh mini              # 正常 SSH 连接（端口转发自动生效）
claude                # 启动 Claude Code
                      # 在本地 Mac 复制图片，远程 Claude Code 中 Ctrl+V 粘贴
```

## 卸载

```bash
# 删除远程 shim
ssh mini 'rm ~/.local/bin/osascript'

# 编辑 ~/.ssh/config，移除 Host mini 下的 RemoteForward 18339 127.0.0.1:18339

# 停止本地服务（可选）
cc-clip service uninstall
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `install.sh` | 一键安装脚本，编译源码 + 配置 + 部署 |
| `osascript-shim.sh` | osascript 拦截器，部署后位于远程 `~/.local/bin/osascript` |
| `cc-clip/` | cc-clip daemon 完整 Go 源码（本地剪贴板 HTTP 服务） |
| `setup-remote-mac.sh` | 仅部署远程 shim（需已安装 cc-clip） |

## 常见问题

**Q: 会影响远程 Mac 上其他使用 osascript 的程序吗？**

不会。shim 只拦截包含 `PNGf`（PNG 图片剪贴板）关键字的请求，其他所有调用直接透传给 `/usr/bin/osascript`。

**Q: 远程是 Linux 怎么办？**

安装脚本会自动检测远程系统。如果是 Linux，会提示你直接使用 `cc-clip setup <host>`。

**Q: token 过期了怎么办？**

重新运行安装脚本即可。

## Acknowledgements

本项目使用 [cc-clip](https://github.com/ShunmeiCho/cc-clip)（MIT License）作为本地剪贴板服务，在其基础上实现了 macOS 远程主机支持。
