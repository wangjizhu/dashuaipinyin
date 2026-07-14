# ============================================================
#  净拼输入法 - 一键安装脚本
#  = 小狼毫 Weasel (TSF 前端 + librime 引擎)
#  + 万象拼音 base 方案 (词库)
#  + 万象语言模型 LTS (整句转换)
#  100% 本地运行 / 无广告 / 零联网零遥测
#  兼容 Windows PowerShell 5.1，需管理员权限运行
# ============================================================
[CmdletBinding()]
param(
    # 跳过下载（dist 目录中已有三个安装件时使用）
    [switch]$SkipDownload,
    # 不备份已有的 %APPDATA%\Rime（默认会备份）
    [switch]$NoBackup
)

$ErrorActionPreference = 'Stop'

# ---------- 常量 ----------
$WeaselVersion = '0.17.4'
$WeaselUrl   = "https://github.com/rime/weasel/releases/download/$WeaselVersion/weasel-$WeaselVersion.0-installer.exe"
$WanxiangUrl = 'https://github.com/amzxyz/rime-wanxiang/releases/download/v16.1.0/rime-wanxiang-base.zip'
$GramUrl     = 'https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram'

$RepoRoot  = Split-Path -Parent $PSScriptRoot
$DistDir   = Join-Path $RepoRoot 'dist'
$RimeUser  = Join-Path $env:APPDATA 'Rime'

$WeaselExe   = Join-Path $DistDir "weasel-$WeaselVersion.0-installer.exe"
$WanxiangZip = Join-Path $DistDir 'rime-wanxiang-base.zip'
$GramFile    = Join-Path $DistDir 'wanxiang-lts-zh-hans.gram'

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

# ---------- 权限检查 ----------
$identity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw '请以管理员身份运行本脚本（注册 TSF 输入法需要管理员权限）。'
}

# ---------- 1. 下载 ----------
if (-not $SkipDownload) {
    Step '下载安装件（已存在则跳过）'
    New-Item -ItemType Directory -Force $DistDir | Out-Null
    $downloads = @(
        @{ Url = $WeaselUrl;   Path = $WeaselExe },
        @{ Url = $WanxiangUrl; Path = $WanxiangZip },
        @{ Url = $GramUrl;     Path = $GramFile }
    )
    foreach ($d in $downloads) {
        if (Test-Path $d.Path) { Write-Host "    已存在: $(Split-Path -Leaf $d.Path)"; continue }
        Write-Host "    下载: $($d.Url)"
        & curl.exe -L --retry 3 -sS -o $d.Path $d.Url
        if ($LASTEXITCODE -ne 0) { throw "下载失败: $($d.Url)" }
    }
}
foreach ($f in @($WeaselExe, $WanxiangZip, $GramFile)) {
    if (-not (Test-Path $f)) { throw "缺少安装件: $f" }
}

# ---------- 2. 静默安装小狼毫 ----------
Step "安装小狼毫 Weasel $WeaselVersion（静默）"
$p = Start-Process -FilePath $WeaselExe -ArgumentList '/S' -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "Weasel 安装程序退出码: $($p.ExitCode)" }

# 定位安装目录（注册表优先，目录扫描兜底）
$weaselRoot = $null
foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Rime\Weasel', 'HKLM:\SOFTWARE\Rime\Weasel') {
    try { $weaselRoot = (Get-ItemProperty -Path $k -ErrorAction Stop).WeaselRoot; if ($weaselRoot) { break } } catch {}
}
if (-not $weaselRoot) {
    $cand = Get-ChildItem 'C:\Program Files (x86)\Rime\weasel-*', 'C:\Program Files\Rime\weasel-*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($cand) { $weaselRoot = $cand.FullName }
}
if (-not $weaselRoot -or -not (Test-Path $weaselRoot)) { throw '未找到小狼毫安装目录' }
Write-Host "    安装目录: $weaselRoot"

# ---------- 3. 部署万象方案 ----------
Step '部署万象拼音方案与语言模型'

# 停掉正在运行的 WeaselServer，避免文件占用
Get-Process WeaselServer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

# 备份既有用户目录（仅首次覆盖前）
if ((Test-Path $RimeUser) -and -not $NoBackup) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bak = "$RimeUser.bak-$stamp"
    Copy-Item $RimeUser $bak -Recurse -Force
    Write-Host "    已备份原配置到: $bak"
}
New-Item -ItemType Directory -Force $RimeUser | Out-Null

# 解压方案（万象 zip 即完整 Rime 用户目录内容）
Expand-Archive -Path $WanxiangZip -DestinationPath $RimeUser -Force
# 语言模型放用户目录根
Copy-Item $GramFile (Join-Path $RimeUser 'wanxiang-lts-zh-hans.gram') -Force
# 应用本仓库的覆盖配置（*.custom.yaml，如有）
$overlay = Join-Path $RepoRoot 'rime-config'
if (Test-Path $overlay) {
    Get-ChildItem $overlay -Filter *.yaml -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName $RimeUser -Force
        Write-Host "    覆盖配置: $($_.Name)"
    }
}

# ---------- 4. 重新部署（编译词库） ----------
Step '编译词库与语言模型（首次约 1-3 分钟）'
$deployer = Join-Path $weaselRoot 'WeaselDeployer.exe'
$p = Start-Process -FilePath $deployer -ArgumentList '/deploy' -Wait -PassThru
Write-Host "    部署器退出码: $($p.ExitCode)"

# 验证编译产物
$built = Join-Path $RimeUser 'build\wanxiang.schema.yaml'
if (Test-Path $built) {
    Write-Host '    部署成功：build\wanxiang.schema.yaml 已生成' -ForegroundColor Green
} else {
    Write-Warning '未检测到编译产物，请打开【小狼毫输入法设定】手动执行重新部署'
}

# 重新拉起服务
$server = Join-Path $weaselRoot 'WeaselServer.exe'
Start-Process -FilePath $server | Out-Null

Step '完成！'
Write-Host ''
Write-Host '  按 Win+空格 切换到【中州韵】即可使用。' -ForegroundColor Green
Write-Host '  建议到 设置 > 时间和语言 > 语言和区域 > 微软拼音选项 中' -ForegroundColor Green
Write-Host '  将中州韵设为默认，或直接卸载不再使用的输入法。' -ForegroundColor Green
