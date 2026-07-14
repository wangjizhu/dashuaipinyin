# ============================================================
#  大帅拼音·极简 TSF 前端 - 安装/卸载脚本
#  安装: 复制到 Program Files → 准备用户目录 → regsvr32 注册
#  卸载: .\setup-mini.ps1 -Uninstall
#  需管理员权限
# ============================================================
[CmdletBinding()]
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$RepoRoot  = Split-Path -Parent $PSScriptRoot
$BuildOut  = Join-Path $RepoRoot 'build-out\mini'
$InstallDir = 'C:\Program Files\DashuaiMini'
$UserDir   = Join-Path $env:APPDATA 'DashuaiMini'
$RimeUser  = Join-Path $env:APPDATA 'Rime'

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

$identity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw '请以管理员身份运行。'
}

if ($Uninstall) {
    Step '反注册 TSF 文本服务'
    if (Test-Path "$InstallDir\DashuaiMini.dll") {
        & regsvr32.exe /u /s "$InstallDir\DashuaiMini.dll"
    }
    Step '删除安装目录（用户词典保留在 %APPDATA%\DashuaiMini）'
    Remove-Item $InstallDir -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host '卸载完成。'
    return
}

foreach ($f in @("$BuildOut\DashuaiMini.dll", "$BuildOut\rime.dll")) {
    if (-not (Test-Path $f)) { throw "缺少 $f，请先运行 build-mini.ps1" }
}
if (-not (Test-Path "$RimeUser\build\wanxiang.table.bin")) {
    throw '未找到已部署的万象词库（%APPDATA%\Rime\build），请先运行 install.ps1'
}

# ---------- 1. 程序文件 ----------
Step "安装到 $InstallDir"
New-Item -ItemType Directory -Force $InstallDir | Out-Null
Copy-Item "$BuildOut\DashuaiMini.dll" $InstallDir -Force
Copy-Item "$BuildOut\rime.dll" $InstallDir -Force
# 共享数据（opencc 等）取自大帅拼音（weasel）安装
$weaselData = 'C:\Program Files\Rime\weasel-0.17.4\data'
if (Test-Path $weaselData) {
    New-Item -ItemType Directory -Force "$InstallDir\data" | Out-Null
    Copy-Item "$weaselData\opencc" "$InstallDir\data\" -Recurse -Force
}

# ---------- 2. 用户目录（独立于小狼毫，避免词典锁冲突） ----------
Step "准备用户目录 $UserDir（复用已编译的万象词库）"
New-Item -ItemType Directory -Force $UserDir | Out-Null
# 复制除 userdb/sync/gram 外的全部内容（含 build\ 编译产物，保留时间戳避免重编译）
# robocopy：/XD *.userdb 排除任意层级的用户词典目录（可能被 WeaselServer 锁定）
& robocopy $RimeUser $UserDir /E /COPY:DAT /R:1 /W:1 `
    /XD '*.userdb' 'sync' /XF 'installation.yaml' 'wanxiang-lts-zh-hans.gram' /NFL /NDL /NJH | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy 失败 (exit $LASTEXITCODE)" }
$global:LASTEXITCODE = 0
# 400MB 语言模型用硬链接（同卷零拷贝）
$gramLink = Join-Path $UserDir 'wanxiang-lts-zh-hans.gram'
if (-not (Test-Path $gramLink)) {
    New-Item -ItemType HardLink -Path $gramLink -Target "$RimeUser\wanxiang-lts-zh-hans.gram" | Out-Null
}

# ---------- 3. 注册 ----------
Step '注册 TSF 文本服务（regsvr32）'
# regsvr32 是 GUI 程序，必须 -Wait 拿真实退出码
$p = Start-Process regsvr32.exe -ArgumentList '/s', "`"$InstallDir\DashuaiMini.dll`"" -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "regsvr32 失败 (exit $($p.ExitCode))" }

# 验证注册表
$tip = "HKLM:\SOFTWARE\Microsoft\CTF\TIP\{DA548A11-0714-4E22-9B0C-3F2A61C0D9E1}"
if (Test-Path $tip) {
    Write-Host '    TSF TIP 注册验证通过' -ForegroundColor Green
} else {
    Write-Warning 'TIP 注册表键未找到，注册可能未成功'
}

Step '完成！按 Win+空格 切换到【大帅拼音·极简】即可试用。'
Write-Host '  卸载: .\setup-mini.ps1 -Uninstall'
