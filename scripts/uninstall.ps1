# ============================================================
#  大帅拼音输入法 - 干净卸载脚本
#  卸载小狼毫本体；可选删除用户词典与配置
#  需管理员权限运行
# ============================================================
[CmdletBinding()]
param(
    # 同时删除 %APPDATA%\Rime 用户目录（含个人词典！默认保留）
    [switch]$PurgeUserData
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw '请以管理员身份运行本脚本。'
}

# 停止服务进程
Get-Process WeaselServer, WeaselDeployer -ErrorAction SilentlyContinue | Stop-Process -Force

# 定位卸载器
$weaselRoot = $null
foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Rime\Weasel', 'HKLM:\SOFTWARE\Rime\Weasel') {
    try { $weaselRoot = (Get-ItemProperty -Path $k -ErrorAction Stop).WeaselRoot; if ($weaselRoot) { break } } catch {}
}
if (-not $weaselRoot) {
    $cand = Get-ChildItem 'C:\Program Files (x86)\Rime\weasel-*', 'C:\Program Files\Rime\weasel-*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($cand) { $weaselRoot = $cand.FullName }
}
if ($weaselRoot) {
    $uninst = Join-Path $weaselRoot 'uninstall.exe'
    if (Test-Path $uninst) {
        Write-Host "==> 静默卸载小狼毫: $uninst"
        Start-Process -FilePath $uninst -ArgumentList '/S' -Wait
    } else {
        Write-Warning "未找到卸载器: $uninst"
    }
} else {
    Write-Warning '未找到小狼毫安装目录（可能已卸载）'
}

if ($PurgeUserData) {
    $rimeUser = Join-Path $env:APPDATA 'Rime'
    if (Test-Path $rimeUser) {
        Remove-Item $rimeUser -Recurse -Force -Confirm:$false
        Write-Host "==> 已删除用户目录: $rimeUser"
    }
} else {
    Write-Host '==> 已保留 %APPDATA%\Rime 用户词典与配置（如需彻底清除请加 -PurgeUserData）'
}

Write-Host '完成。'
