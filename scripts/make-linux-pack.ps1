# ============================================================
#  大帅拼音输入法 - Linux 数据包构建
#  从本机 %APPDATA%\Rime 组装跨平台 Rime 数据（方案+词库+lua+语言模型），
#  经 WSL tar 打成 dashuai-pinyin-<版本>-rime-data.tar.gz 供 Ubuntu 安装脚本使用。
#  排除：build/（目标机现场编译，librime 版本不同）、*.userdb（用户状态）、
#        weasel*/installation/user.yaml（Windows/本机专属）
#  前置：WSL（任一发行版，只用它的 tar/gzip）
# ============================================================
[CmdletBinding()]
param([string]$Version = '0.17.4.1')

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$OutDir   = Join-Path $RepoRoot 'build-out'
$OutName  = "dashuai-pinyin-$Version-rime-data.tar.gz"

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

New-Item -ItemType Directory -Force $OutDir | Out-Null

$bash = @'
set -e
SRC='/mnt/c/Users/Administrator/AppData/Roaming/Rime'
STAGE=/tmp/dashuai-pack
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$SRC"/default.yaml "$SRC"/custom_phrase.txt "$SRC"/wanxiang*.yaml "$SRC"/README.md "$SRC"/version.txt "$STAGE"/
cp -r "$SRC"/dicts "$STAGE"/
mkdir -p "$STAGE/lua"
(cd "$SRC/lua" && find . -name '*.userdb' -prune -o -type f -print0 | tar --null -T - -cf -) | tar -xf - -C "$STAGE/lua"
cp "$SRC"/wanxiang-lts-zh-hans.gram "$STAGE"/
# Linux 适配：wanxiang.super_lookup 在发行版 librime-lua(~2023) 上初始化失败
# 且每键刷错误日志，从 filters 里移除（其余与 Windows 完全一致）
python3 - "$STAGE/wanxiang.custom.yaml" <<'PYEOF'
import sys, io
p = sys.argv[1]
s = io.open(p, encoding='utf-8').read().replace('\r\n', '\n')
old = """  engine/filters/+:
    - lua_filter@*dashuai_greedy"""
new = """  # Linux 适配（打包时自动生成）：移除 super_lookup（发行版 librime-lua 不兼容，
  # 初始化失败且每键报错），其余 filters 与 Windows 版完全一致。
  engine/filters:
    - lua_filter@*wanxiang.auto_phrase
    - lua_filter@*wanxiang.super_english
    - lua_filter@*wanxiang.charset_filter
    - lua_filter@*wanxiang.super_comment_preedit
    - lua_filter@*wanxiang.super_replacer
    - lua_filter@*wanxiang.super_filter
    - lua_filter@*wanxiang.super_sequence*F
    - lua_filter@*wanxiang.user_predict*F
    - uniquifier
    - lua_filter@*dashuai_greedy"""
assert old in s, 'engine/filters/+ pattern not found in wanxiang.custom.yaml'
io.open(p, 'w', encoding='utf-8').write(s.replace(old, new))
print('patched: wanxiang.custom.yaml (linux filters, super_lookup removed)')
PYEOF
du -sh "$STAGE"
tar -C "$STAGE" -czf "/mnt/c/OUT_PLACEHOLDER" .
'@

$outWsl = ($OutDir -replace '^C:\\','' -replace '\\','/') + "/$OutName"
$bash = $bash -replace 'OUT_PLACEHOLDER', $outWsl
$tmpSh = Join-Path $env:TEMP 'dashuai-linux-pack.sh'
[IO.File]::WriteAllText($tmpSh, ($bash -replace "`r`n","`n"), (New-Object System.Text.UTF8Encoding($false)))
$tmpShWsl = '/mnt/c' + ($tmpSh -replace '^C:','' -replace '\\','/')

Step "组装并打包（gzip 400MB 语言模型，约 1-3 分钟）"
wsl -u root -- bash -c "tr -d '\r' < '$tmpShWsl' > /tmp/pack.sh; bash /tmp/pack.sh"
if ($LASTEXITCODE -ne 0) { throw "WSL 打包失败 (exit $LASTEXITCODE)" }

$out = Join-Path $OutDir $OutName
if (-not (Test-Path $out)) { throw "未生成 $out" }
Step ("完成: build-out\{0} ({1:N1} MB)" -f $OutName, ((Get-Item $out).Length/1MB))
