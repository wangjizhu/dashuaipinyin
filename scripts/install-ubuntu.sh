#!/usr/bin/env bash
# ============================================================
#  大帅拼音输入法 - Ubuntu 一键安装
#  前端：ibus-rime（Ubuntu/GNOME 默认，推荐）或 fcitx5-rime
#  引擎：系统 librime + octagram(语言模型) + lua 插件
#  数据：与 Windows 版完全同源（万象方案 + 语言模型 + 大帅定制）
#
#  用法：
#    ./install-ubuntu.sh                 # 自动选择前端（默认 ibus）
#    ./install-ubuntu.sh fcitx5          # 使用 fcitx5-rime
#    ./install-ubuntu.sh ibus 本地数据包.tar.gz   # 离线安装（跳过下载）
#
#  要求：Ubuntu 24.04 及以上（librime >= 1.8.5；22.04 的 1.7.3 实测不可用）
# ============================================================
set -euo pipefail

VERSION="0.17.4.1"
DATA_URL="https://github.com/wangjizhu/dashuaipinyin/releases/download/v${VERSION}/dashuai-pinyin-${VERSION}-ubuntu-rime-data.tar.gz"

FRONTEND="${1:-auto}"
LOCAL_DATA="${2:-}"

say() { printf '\033[36m==> %s\033[0m\n' "$*"; }

# ---------- 0. 环境检查 ----------
if ! command -v apt-get >/dev/null; then
    echo "错误：未找到 apt-get，本脚本仅支持 Ubuntu/Debian 系。" >&2; exit 1
fi
if [ "$(id -u)" = 0 ]; then
    echo "错误：请以普通用户运行（脚本内部会用 sudo 安装系统包）。" >&2; exit 1
fi

# librime 版本闸门：万象方案要求 librime >= 1.8.5。
# Ubuntu 22.04 仓库是 1.7.3（配套 librime-lua 过旧），实测症状 = 部署成功但
# 候选全空 + lua 错误刷屏，所以直接拒绝，不让用户装出一个哑巴输入法。
LIBRIME_CAND="$(apt-cache policy librime-plugin-lua 2>/dev/null | awk '/Candidate:/ {print $2}')"
if [ -z "$LIBRIME_CAND" ] || [ "$LIBRIME_CAND" = "(none)" ]; then
    echo "错误：本系统源里没有 librime-plugin-lua，无法安装。" >&2; exit 1
fi
if ! dpkg --compare-versions "$LIBRIME_CAND" ge 1.8.5; then
    echo "错误：本系统 librime 版本过旧（$LIBRIME_CAND，需要 >= 1.8.5）。" >&2
    echo "      Ubuntu 22.04 及更早版本不受支持，请使用 Ubuntu 24.04 或更新版本。" >&2
    exit 1
fi

if [ "$FRONTEND" = auto ]; then
    if pgrep -x fcitx5 >/dev/null 2>&1; then FRONTEND=fcitx5; else FRONTEND=ibus; fi
fi

case "$FRONTEND" in
    ibus)   RIME_DIR="$HOME/.config/ibus/rime" ;;
    fcitx5) RIME_DIR="$HOME/.local/share/fcitx5/rime" ;;
    *) echo "错误：前端只能是 ibus 或 fcitx5，收到：$FRONTEND" >&2; exit 1 ;;
esac
say "前端：$FRONTEND    Rime 用户目录：$RIME_DIR"

# ---------- 1. 安装系统包 ----------
say "安装输入法前端与 librime 插件（需要 sudo）"
sudo apt-get update -qq
if [ "$FRONTEND" = fcitx5 ]; then
    sudo apt-get install -y fcitx5-rime librime-plugin-octagram librime-plugin-lua librime-bin
else
    sudo apt-get install -y ibus-rime librime-plugin-octagram librime-plugin-lua librime-bin
fi

# ---------- 2. 获取数据包 ----------
if [ -n "$LOCAL_DATA" ]; then
    DATA_FILE="$LOCAL_DATA"
    [ -f "$DATA_FILE" ] || { echo "错误：本地数据包不存在：$DATA_FILE" >&2; exit 1; }
    say "使用本地数据包：$DATA_FILE"
else
    DATA_FILE="$(mktemp -d)/rime-data.tar.gz"
    say "下载数据包（约 430MB，词库+语言模型全内置）"
    curl -L --retry 3 -o "$DATA_FILE" "$DATA_URL"
fi

# ---------- 3. 部署数据 ----------
if [ -d "$RIME_DIR" ] && [ -n "$(ls -A "$RIME_DIR" 2>/dev/null)" ]; then
    BAK="$RIME_DIR.bak-$(date +%Y%m%d-%H%M%S)"
    say "备份已有配置到 $BAK"
    mv "$RIME_DIR" "$BAK"
fi
mkdir -p "$RIME_DIR"
say "解压数据到 $RIME_DIR"
tar -xzf "$DATA_FILE" -C "$RIME_DIR"

# ---------- 4. 预编译词库（免得首次启用时干等） ----------
say "编译词库与语言模型（一次性，约 1-3 分钟）"
rime_deployer --build "$RIME_DIR" /usr/share/rime-data >/dev/null 2>&1 || \
    rime_deployer --build "$RIME_DIR" >/dev/null 2>&1
[ -f "$RIME_DIR/build/wanxiang.table.bin" ] || {
    echo "错误：词库编译失败（未生成 build/wanxiang.table.bin）" >&2; exit 1; }

# ---------- 5. 品牌化：显示名「大帅拼音」+ 图标「帅」 ----------
say "设置显示名称与图标"
sudo mkdir -p /usr/share/dashuai-pinyin
if [ -f "$RIME_DIR/dashuai-pinyin.png" ]; then
    sudo cp "$RIME_DIR/dashuai-pinyin.png" /usr/share/dashuai-pinyin/dashuai-pinyin.png
fi
if [ "$FRONTEND" = ibus ]; then
    # ibus 引擎注册表：longname=输入源列表显示名，symbol=顶栏指示字符，icon=图标
    # 注意：ibus-rime 包升级会还原此文件，重跑本脚本即可恢复品牌化
    RIME_XML=/usr/share/ibus/component/rime.xml
    if [ -f "$RIME_XML" ]; then
        sudo sed -i \
            -e 's|<longname>.*</longname>|<longname>大帅拼音</longname>|' \
            -e 's|<description>Rime Input Method Engine</description>|<description>大帅拼音输入法</description>|' \
            -e 's|<icon>.*</icon>|<icon>/usr/share/dashuai-pinyin/dashuai-pinyin.png</icon>|' \
            -e 's|<symbol>.*</symbol>|<symbol>帅</symbol>|' \
            "$RIME_XML"
    fi
else
    # fcitx5：用户级 inputmethod 配置覆盖系统默认（无需改系统文件）
    IM_DIR="$HOME/.local/share/fcitx5/inputmethod"
    mkdir -p "$IM_DIR"
    cat > "$IM_DIR/rime.conf" <<'IMEOF'
[InputMethod]
Name=大帅拼音
Icon=/usr/share/dashuai-pinyin/dashuai-pinyin.png
Label=帅
LangCode=zh_CN
Addon=rime
Configurable=True
IMEOF
fi

# ---------- 6. 收尾提示 ----------
say "安装完成！"
echo
if [ "$FRONTEND" = ibus ]; then
    cat <<'EOF'
  启用步骤（GNOME 桌面）：
    1. 注销并重新登录（让 ibus 加载新引擎与显示名）
    2. 设置 → 键盘 → 输入源 → + → 中文 → 中文（大帅拼音）
    3. Super+空格 切换即可打字，顶栏显示「帅」
EOF
else
    cat <<'EOF'
  启用步骤（fcitx5）：
    1. 重启 fcitx5：  fcitx5 -r -d
    2. fcitx5-configtool → 添加「大帅拼音」到输入法列表
    3. Ctrl+空格 切换即可打字
EOF
fi
echo
echo "  常用操作与热键见仓库 README：https://github.com/wangjizhu/dashuaipinyin"
