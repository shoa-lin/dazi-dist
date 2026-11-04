#!/bin/sh
# dazi（搭子）安装脚本。
#
# 设计约束（宪法第十条：CLI 优先 · 人机同构）：
#   · 不要 root，不碰系统目录 —— 默认装到 ~/.local/bin
#   · 装预编译二进制：纯静态、15MB，不需要 Go 工具链，也不吃内存
#     （从源码编译峰值要 839MB，很多小机器扛不住 —— 那不该是安装的门槛）
#   · 下完校验 SHA256，对不上就退出，不装
#     这层校验能挡什么、挡不了什么要说清：二进制和 SHA256SUMS 来自同一个发布源，
#     所以它挡的是传输损坏和"只换了其中一个文件"，挡不了发布源本身被控制
#     （那种情况下两个文件会被一起换掉）。要防到那一层得有离线可验的发布签名，
#     现在还没有。
#   · 装完不自动连任何中枢，也不生成任何身份 —— 那是你的决定
#
# 运行前提（精简镜像上未必都有）：curl 或 wget、uname、mktemp、grep、awk、cp、mv、
# chmod、mkdir，以及 sha256sum 或 shasum 之一。shell 本身只用 POSIX 语法，
# dash / BusyBox ash 都能跑。
#
# 用法：
#   curl -fsSL https://raw.githubusercontent.com/shoa-lin/dazi-dist/main/install.sh | sh
#   DAZI_PREFIX=/usr/local sh install.sh          # 换安装位置
#   DAZI_VERSION=v0.1.0-r5 sh install.sh          # 装某个版本（默认最新）
set -eu

DIST="${DAZI_DIST:-shoa-lin/dazi-dist}"
VERSION="${DAZI_VERSION:-latest}"
PREFIX="${DAZI_PREFIX:-$HOME/.local}"
# 规范成绝对路径：相对前缀（DAZI_PREFIX=.）会让下面那段 PATH 判断拿字面量
# "./bin" 去比一串绝对目录，即使它已经在 PATH 里也判成不在。
case "$PREFIX" in
/*) ;;
*) PREFIX="$(cd "$PREFIX" 2>/dev/null && pwd)" || PREFIX="$PWD/${DAZI_PREFIX}" ;;
esac
BINDIR="$PREFIX/bin"

say() { printf '%s\n' "$*"; }
die() { printf '✗ %s\n' "$*" >&2; exit 1; }

# 取文件：curl 或 wget 都行。
#
# 为什么要管 wget：Alpine / BusyBox 镜像自带的是 wget 而不是 curl，而 Agent
# 很常跑在这种精简容器里。只认 curl 就等于把那批环境挡在门外。
if command -v curl >/dev/null 2>&1; then
	fetch() { curl -fsSL -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
	# BusyBox 的 wget 不验证 TLS 证书（它自己会打印 "TLS certificate
	# validation not implemented"）。那意味着没有任何认证：中间人可以同时
	# 换掉二进制和 SHA256SUMS，校验照样通过 —— 校验和与二进制同源，它防的
	# 是损坏，不是伪造，伪造要靠 TLS 挡住。所以这里必须拦，不能只警告：
	# 装进来的是可执行文件，默默往下走等于把这台机器交出去。
	if wget --version 2>&1 | grep -qi busybox; then
		die "这台机器上的 wget 是 BusyBox 版，它不验证 TLS 证书。
    没有证书校验就等于没有认证 —— 中间人能同时换掉二进制和校验和文件，
    SHA256 比对一样会通过。所以拒绝继续。

    装个会验证证书的下载工具再来：
      apk add curl          # Alpine
      apt install curl      # Debian / Ubuntu"
	fi
	fetch() { wget -qO "$2" "$1"; }
else
	die "需要 curl 或 wget"
fi

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

say "下载 ${asset}（${VERSION}）…"
fetch "$url/$asset" "$tmp/dazi" ||
	die "下载失败：$url/$asset
    这个平台可能还没发布对应的二进制，看一眼 $base"

# ── 校验：对不上就不装 ──
say "校验 SHA256…"
fetch "$url/SHA256SUMS" "$tmp/SHA256SUMS" || die "下载校验文件失败"
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

mkdir -p "$BINDIR" || die "建不了目录 $BINDIR"

# 落地分两步，为的是最后那一下是**同目录内**的 rename —— 同目录才保证原子，
# 这样升级过程里不会有哪个瞬间 $BINDIR/dazi 是半个文件。
#
# 所以中转文件必须落在 $BINDIR 里，不能直接从 $tmp 搬：mktemp -d 常在 /tmp，
# 而 /tmp 在很多系统上是 tmpfs，跨文件系统的 mv 会退化成"复制再删除"，
# 中途断掉就留下一个半截的 dazi。先 cp 进 $BINDIR（可以不原子，反正是临时名），
# 再在同目录内 rename。
staged="$BINDIR/.dazi.new.$$"
# 这个中转文件在 $BINDIR 里，$tmp 的 trap 管不到它，得自己兜
trap 'rm -rf "$tmp"; rm -f "$staged"' EXIT
cp "$tmp/dazi" "$staged" || die "写不进 $BINDIR（磁盘满？没权限？）"
chmod 0755 "$staged" || die "改权限失败：$staged"
mv -f "$staged" "$BINDIR/dazi" || die "落地失败：$BINDIR/dazi"

# 跑一下它自己报版本。这不只是展示 —— 装完却跑不起来（架构不符、
# 被安全策略拦下）的话，上面那句"已装到"就是在骗人，所以失败要如实说。
say ""
if "$BINDIR/dazi" version; then
	say "✓ 已装到 $BINDIR/dazi"
else
	die "文件已落在 $BINDIR/dazi，但跑不起来
    架构不符，或被系统的安全策略拦下了。先手动跑一次看报什么：
      $BINDIR/dazi version"
fi

case ":$PATH:" in
*":$BINDIR:"*) ;;
*)
	say ""
	say "把它加进 PATH（当前 shell 没有 ${BINDIR}）："
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
