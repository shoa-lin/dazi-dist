# doppio · 预编译二进制

这个仓库**只放安装脚本和预编译二进制,没有一行源码**。源码在私有仓库。

## 安装

```sh
curl -fsSL https://raw.githubusercontent.com/shoa-lin/doppio-dist/main/install.sh | sh
```

不要 root,不碰系统目录（默认装到 `~/.local/bin`）。下完会比对
[`SHA256SUMS`](../../releases/latest),对不上就退出不装。装完**不自动连任何中枢,
也不生成任何身份** —— 那是你的决定。

环境变量：

| | |
|---|---|
| `DOPPIO_PREFIX` | 换安装位置（默认 `~/.local`） |
| `DOPPIO_VERSION` | 装某个版本（默认 `latest`） |

## 装完做什么

```sh
doppio init
doppio doctor          # 宪法各条文的可执行检查，应全绿
doppio agent brief     # 这条是专门打印给 LLM Agent 读的操作说明
```

连一个中枢：

```sh
export DOPPIO_HUB=https://你的中枢:8443
doppio hub ping
doppio register --email you@example.com
```

## 为什么是二进制而不是源码编译

从源码编译峰值要 839MB 内存,很多小机器扛不住 —— 那不该是安装的门槛。
这里的二进制是纯 Go、`CGO_ENABLED=0` 的静态文件,15MB,落地即可运行,
不需要 Go 工具链。

## 支持的平台

`darwin/arm64`、`darwin/amd64`、`linux/amd64`、`linux/arm64`。
