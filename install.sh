#!/bin/sh
# dazi（搭子）安装脚本。
#
# 设计约束（宪法第十条：CLI 优先 · 人机同构）：
#   · 不要 root，不碰系统目录 —— 默认装到 ~/.local/bin
#   · 装预编译二进制：纯静态、15MB，不需要 Go 工具链，也不吃内存
#     （从源码编译峰值要 839MB，很多小机器扛不住 —— 那不该是安装的门槛）
#   · 下完校验 SHA256，对不上就退出，不装
#   · 装完不自动连任何中枢，也不生成任何身份 —— 那是你的决定
#
# 用法：
#   curl -fsSL https://raw.githubusercontent.com/shoa-lin/dazi-dist/main/install.sh | sh
#   DAZI_PREFIX=/usr/local sh install.sh          # 换安装位置
#   DAZI_VERSION=v0.1.0-r5 sh install.sh          # 装某个版本（默认最新）
set -eu

DIST="${DAZI_DIST:-shoa-lin/dazi-dist}"
VERSION="${DAZI_VERSION:-latest}"
PREFIX="${DAZI_PREFIX:-$HOME/.local}"
BINDIR="$PREFIX/bin"

say() { printf '%s\n' "$*"; }
die() { printf '✗ %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "需要 curl"

case "$(uname -s)" in
Darwin) os=darwin ;;
Linux) os=linux ;;
*) die "暂不支持的系统 $(uname -s)" ;;
esac
case "$(uname -m)" in
arm64 | aarch64) arch=arm64 ;;
x86_64 | amd64) arch=amd64 ;;
*) die "暂不支持的架构 $(uname -m)" ;;
esac
asset="dazi_${os}_${arch}"

base="https://github.com/$DIST/releases"
if [ "$VERSION" = latest ]; then
	url="$base/latest/download"
else
	url="$base/download/$VERSION"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

say "下载 $asset（$VERSION）…"
curl -fsSL -o "$tmp/dazi" "$url/$asset" ||
	die "下载失败：$url/$asset
    这个平台可能还没发布对应的二进制，看一眼 $base"

# ── 校验：对不上就不装 ──
say "校验 SHA256…"
curl -fsSL -o "$tmp/SHA256SUMS" "$url/SHA256SUMS" || die "下载校验文件失败"
want="$(grep " $asset\$" "$tmp/SHA256SUMS" | awk '{print $1}')"
[ -n "$want" ] || die "校验文件里没有 $asset 这一项"
if command -v sha256sum >/dev/null 2>&1; then
	got="$(sha256sum "$tmp/dazi" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
	got="$(shasum -a 256 "$tmp/dazi" | awk '{print $1}')"
else
	die "既没有 sha256sum 也没有 shasum，无法校验 —— 拒绝装一个没校验过的二进制"
fi
[ "$got" = "$want" ] || die "SHA256 不符，拒绝安装
    期望 $want
    实得 $got"
say "✓ 校验通过"

mkdir -p "$BINDIR"
# 先写临时名再改名：换名是原子的，这样升级时不会出现"装了一半的 dazi"
mv "$tmp/dazi" "$BINDIR/.dazi.new"
chmod 0755 "$BINDIR/.dazi.new"
mv "$BINDIR/.dazi.new" "$BINDIR/dazi"

say ""
say "✓ 已装到 $BINDIR/dazi"
"$BINDIR/dazi" version || true

case ":$PATH:" in
*":$BINDIR:"*) ;;
*)
	say ""
	say "把它加进 PATH（当前 shell 没有 $BINDIR）："
	say "  export PATH=\"$BINDIR:\$PATH\""
	;;
esac

cat <<'NEXT'

接下来（都不需要管理员权限，数据在 ~/.dazi）：

  dazi init                          # 建本机数据目录
  dazi doctor                        # 宪法各条文的可执行检查，应全绿
  dazi agent brief                   # 这条是专门打印给 LLM Agent 读的操作说明

连一个中枢（比如朋友或团队起的）：
  export DAZI_HUB=https://hub.example.com
  dazi hub ping
  dazi register --email you@example.com
  dazi login    --email you@example.com
  dazi agent enroll-init --kind claude-code      # 人类签发入列码
  dazi agent enroll --code <码> --skill go       # Agent 侧入列，私钥只留本机

自己起一个中枢：
  dazi hub serve --addr 0.0.0.0:8443 \
    --tls-cert cert.pem --tls-key key.pem --trust-proxy cloudflare

一切能力都在原子操作层，`dazi ops list` 同时就是 HTTP 接口的文档。
NEXT
