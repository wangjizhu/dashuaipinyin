# ============================================================
#  大帅拼音输入法 - 一键安装脚本
#  = 小狼毫 Weasel (TSF 前端 + librime 引擎)
#  + 万象拼音 base 方案 (词库)
#  + 万象语言模型 LTS (整句转换)
#  100% 本地运行 / 无广告 / 零联网零遥测
#  兼容 Windows PowerShell 5.1（64 位），需管理员权限运行
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
if (-not [Environment]::Is64BitProcess) {
    throw '请使用 64 位 PowerShell 运行（需要加载 64 位 rime.dll 执行部署）。'
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
# 注意：不能用 Start-Process -Wait —— PS 5.1 会连同子进程一起等，
# 而 NSIS 安装器结尾会拉起常驻的 WeaselServer，导致永久挂起。
$p = Start-Process -FilePath $WeaselExe -ArgumentList '/S' -PassThru
$p.WaitForExit()
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

# ---------- 2.5 品牌化：语言栏显示名改为"大帅拼音" ----------
# TSF 输入法在语言栏/输入法切换列表的名字来自注册表 LanguageProfile 的 Description。
# 每次重装 weasel 都会注册回"小狼毫"，所以此步骤必须在安装之后执行。
Step '设置显示名称：大帅拼音'
$tipGuid = '{A3F4CDED-B1E9-41EE-9CA6-7B4D0DE6CB0A}'
foreach ($ctfRoot in @("HKLM:\SOFTWARE\Microsoft\CTF\TIP\$tipGuid\LanguageProfile",
                       "HKLM:\SOFTWARE\WOW6432Node\Microsoft\CTF\TIP\$tipGuid\LanguageProfile")) {
    if (-not (Test-Path $ctfRoot)) { continue }
    Get-ChildItem $ctfRoot | ForEach-Object {
        Get-ChildItem $_.PSPath | ForEach-Object {
            Set-ItemProperty -Path $_.PSPath -Name Description -Value '大帅拼音'
        }
    }
}
Write-Host '    显示名已设为“大帅拼音”（注销重新登录后全面生效）'

# ---------- 3. 部署万象方案文件 ----------
Step '部署万象拼音方案与语言模型'

# 停掉正在运行的 WeaselServer / WeaselDeployer，避免文件占用
Get-Process WeaselServer, WeaselDeployer -ErrorAction SilentlyContinue | Stop-Process -Force -Confirm:$false
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
# 应用本仓库的覆盖配置（*.custom.yaml + lua 扩展）
$overlay = Join-Path $RepoRoot 'rime-config'
if (Test-Path $overlay) {
    Get-ChildItem $overlay -Filter *.yaml -File -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName $RimeUser -Force
        Write-Host "    覆盖配置: $($_.Name)"
    }
    if (Test-Path "$overlay\lua") {
        New-Item -ItemType Directory -Force "$RimeUser\lua" | Out-Null
        Copy-Item "$overlay\lua\*" "$RimeUser\lua\" -Recurse -Force
        Write-Host "    覆盖配置: lua\ 扩展脚本"
    }
}

# 关键：Expand-Archive 保留 zip 内部的旧时间戳，librime 的 detect_modifications
# 按 mtime 判断是否需要重新编译，不刷新会导致部署被静默跳过。
$now = Get-Date
Get-ChildItem $RimeUser -Recurse -File |
    Where-Object { $_.FullName -notmatch '\\build\\' } |
    ForEach-Object { $_.LastWriteTime = $now }

# ---------- 4. 编译词库（直接调用 librime C API） ----------
# 不用 WeaselDeployer.exe /deploy：实测它可能静默不执行编译。
# 直接 P/Invoke rime.dll 的部署接口，同步等待编译完成，成败明确。
Step '编译词库与语言模型（首次约 30 秒 - 3 分钟）'

$csharp = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class RimeDeployer
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RimeTraits
    {
        public int data_size;
        public IntPtr shared_data_dir;
        public IntPtr user_data_dir;
        public IntPtr distribution_name;
        public IntPtr distribution_code_name;
        public IntPtr distribution_version;
        public IntPtr app_name;
        public IntPtr modules;
        public int min_log_level;
        public IntPtr log_dir;
        public IntPtr prebuilt_data_dir;
        public IntPtr staging_dir;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetDllDirectory(string lpPathName);

    [DllImport("rime.dll")] private static extern void RimeSetup(ref RimeTraits t);
    [DllImport("rime.dll")] private static extern void RimeInitialize(ref RimeTraits t);
    [DllImport("rime.dll")] private static extern int RimeStartMaintenance(int fullCheck);
    [DllImport("rime.dll")] private static extern void RimeJoinMaintenanceThread();
    [DllImport("rime.dll")] private static extern void RimeFinalize();

    private static IntPtr U8(string s)
    {
        if (s == null) return IntPtr.Zero;
        byte[] bytes = Encoding.UTF8.GetBytes(s + "\0");
        IntPtr p = Marshal.AllocHGlobal(bytes.Length);
        Marshal.Copy(bytes, 0, p, bytes.Length);
        return p;
    }

    // 返回值：1 = 执行了维护(编译)，0 = 无需维护
    public static int Deploy(string weaselRoot, string sharedDataDir, string userDataDir, string logDir)
    {
        SetDllDirectory(weaselRoot);
        RimeTraits t = new RimeTraits();
        t.data_size = Marshal.SizeOf(typeof(RimeTraits)) - 4;
        t.shared_data_dir = U8(sharedDataDir);
        t.user_data_dir = U8(userDataDir);
        t.distribution_name = U8("Weasel");
        t.distribution_code_name = U8("weasel");
        t.distribution_version = U8("0.17.4");
        t.app_name = U8("rime.weasel");
        t.min_log_level = 0;
        t.log_dir = U8(logDir);
        RimeSetup(ref t);
        RimeInitialize(ref t);
        int started = RimeStartMaintenance(1);
        if (started != 0) { RimeJoinMaintenanceThread(); }
        RimeFinalize();
        return started;
    }
}
'@
Add-Type -TypeDefinition $csharp -Language CSharp

$logDir = Join-Path $env:TEMP 'rime.dashuai-install'
New-Item -ItemType Directory -Force $logDir | Out-Null
$sharedData = Join-Path $weaselRoot 'data'
$ret = [RimeDeployer]::Deploy($weaselRoot, $sharedData, $RimeUser, $logDir)
Write-Host "    部署返回: $ret (1=已编译, 0=无需编译)"

# 验证编译产物
$built = Join-Path $RimeUser 'build\wanxiang.table.bin'
if (Test-Path $built) {
    $mb = [math]::Round((Get-Item $built).Length / 1MB, 1)
    Write-Host "    部署成功：build\wanxiang.table.bin ($mb MB)" -ForegroundColor Green
} else {
    throw "部署失败：未生成 build\wanxiang.table.bin，请查看日志 $logDir"
}

# ---------- 5. 启动服务 ----------
$server = Join-Path $weaselRoot 'WeaselServer.exe'
Start-Process -FilePath $server | Out-Null

Step '完成！'
Write-Host ''
Write-Host '  按 Win+空格 切换到【中州韵】即可使用大帅拼音。' -ForegroundColor Green
Write-Host '  建议到 设置 > 时间和语言 > 语言和区域 中调整输入法顺序，' -ForegroundColor Green
Write-Host '  或卸载不再使用的第三方输入法。' -ForegroundColor Green
