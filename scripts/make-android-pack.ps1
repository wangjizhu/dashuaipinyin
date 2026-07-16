# ============================================================
#  大帅拼音输入法 - Android 数据包构建
#  从本机 %APPDATA%\Rime 组装 Rime 数据（方案+词库+lua+语言模型）
#  + 万象配套 Trime 皮肤（rime-config\android\，简纯+），
#  打成 dashuai-pinyin-<版本>-android-rime-data.zip，
#  供 同文输入法 Trime（内置 librime + lua + octagram + predict）使用。
#
#  与 Linux 包的差异：Trime 的 librime-lua 是新版，无需移除 super_lookup，
#  配置与 Windows 完全一致；另附 Trime 皮肤与 安装说明.txt。
#  前置：已安装小狼毫（借用其 7z.exe 打 UTF-8 文件名 zip）
# ============================================================
[CmdletBinding()]
param([string]$Version = '0.17.4.2')

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$RimeUser = Join-Path $env:APPDATA 'Rime'
$OutDir   = Join-Path $RepoRoot 'build-out'
$OutName  = "dashuai-pinyin-$Version-android-rime-data.zip"
$SevenZip = 'C:\Program Files\Rime\weasel-0.17.4\7z.exe'
$Stage    = Join-Path $env:TEMP 'dashuai-android-pack'

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

if (-not (Test-Path $SevenZip)) { throw "未找到 7z.exe: $SevenZip" }
New-Item -ItemType Directory -Force $OutDir | Out-Null
if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force -Confirm:$false }
New-Item -ItemType Directory -Force $Stage | Out-Null

# ---------- 1. Rime 数据（与桌面版同源） ----------
Step '组装 Rime 数据'
$topFiles = @('default.yaml','custom_phrase.txt','README.md','version.txt') +
            (Get-ChildItem $RimeUser -Filter 'wanxiang*.yaml' -File | ForEach-Object Name)
foreach ($f in $topFiles) { Copy-Item (Join-Path $RimeUser $f) $Stage -Force }
& robocopy "$RimeUser\dicts" "$Stage\dicts" /E /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy dicts 失败 ($LASTEXITCODE)" }
& robocopy "$RimeUser\lua" "$Stage\lua" /E /XD '*.userdb' /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy lua 失败 ($LASTEXITCODE)" }
$global:LASTEXITCODE = 0
# 语言模型：硬链接零拷贝（7z 打包时读内容）
New-Item -ItemType HardLink -Path (Join-Path $Stage 'wanxiang-lts-zh-hans.gram') `
    -Target (Join-Path $RimeUser 'wanxiang-lts-zh-hans.gram') | Out-Null

# ---------- 2. Trime 皮肤（万象配套「简纯+」，CC-BY-4.0） ----------
Step '附加 Trime 皮肤'
& robocopy "$RepoRoot\rime-config\android" $Stage /E /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy android 皮肤失败 ($LASTEXITCODE)" }
$global:LASTEXITCODE = 0

# ---------- 3. 安装说明 ----------
$readme = @"
大帅拼音 · 安卓数据包（配合开源前端 同文输入法 Trime 使用）

安装步骤：
1. 安装同文输入法（Trime，开源 GPL-3.0）：
   https://github.com/osfans/trime/releases 下载最新 APK 并安装
2. 首次打开 Trime，按提示授予存储权限，选择/新建 rime 文件夹
3. 将本压缩包内的全部文件解压到该 rime 文件夹（提示重名时全部覆盖）
4. 回到 Trime 首页 → 方案 → 勾选「万象拼音」（其他取消勾选）→ 点击部署
   ⚠ 首次部署约 1-2 分钟，期间键盘无响应属正常，等待“部署成功”提示
5. 在 Trime 首页 → 主题 中选择「简纯+」获得配套键盘布局
6. 系统设置 → 输入法 中启用同文输入法并切换使用

说明：
- 词库、语言模型与桌面版（Windows/Ubuntu）完全同源，整句转换与
  候选排序行为一致
- Trime 内置 librime 引擎与 lua / octagram（语言模型）插件，无需额外安装
- 应用名显示为「同文输入法」，输入内核即大帅拼音

常用操作与热键：https://github.com/wangjizhu/dashuaipinyin
"@
[IO.File]::WriteAllText((Join-Path $Stage '安装说明.txt'), $readme, (New-Object System.Text.UTF8Encoding($true)))

# ---------- 4. 打 zip（7z：UTF-8 文件名，兼容安卓解压工具） ----------
Step '打包 zip（含 400MB 语言模型，约 1-3 分钟）'
$out = Join-Path $OutDir $OutName
if (Test-Path $out) { Remove-Item $out -Force -Confirm:$false }
Push-Location $Stage
& $SevenZip a -tzip -mcu=on "$out" * | Select-Object -Last 3
$ret = $LASTEXITCODE
Pop-Location
if ($ret -ne 0) { throw "7z 打包失败 ($ret)" }
Step ("完成: build-out\$OutName ({0:N1} MB)" -f ((Get-Item $out).Length/1MB))
