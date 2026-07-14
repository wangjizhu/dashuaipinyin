# ============================================================
#  大帅拼音输入法 - 品牌化二进制部署脚本
#  把 build-out\ 里自编译的大帅拼音替换进现有小狼毫安装目录。
#  需管理员权限、64 位 PowerShell。
# ============================================================
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$OutDir   = Join-Path $RepoRoot 'build-out'
$RimeUser = Join-Path $env:APPDATA 'Rime'

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

$identity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw '请以管理员身份运行。'
}
if (-not [Environment]::Is64BitProcess) { throw '请使用 64 位 PowerShell。' }

# 定位安装目录
$weaselRoot = $null
foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Rime\Weasel', 'HKLM:\SOFTWARE\Rime\Weasel') {
    try { $weaselRoot = (Get-ItemProperty -Path $k -ErrorAction Stop).WeaselRoot; if ($weaselRoot) { break } } catch {}
}
if (-not $weaselRoot -or -not (Test-Path $weaselRoot)) { throw '未找到小狼毫/大帅拼音安装目录' }
Step "目标安装目录: $weaselRoot"

foreach ($f in @('WeaselServer.exe','weaselx64.dll','rime.dll')) {
    if (-not (Test-Path (Join-Path $OutDir $f))) { throw "build-out 缺少 $f，请先运行 build-dashuai.ps1" }
}

# ---------- 1. 停服务 ----------
Step '停止输入法服务'
Get-Process WeaselServer, WeaselDeployer -ErrorAction SilentlyContinue | Stop-Process -Force -Confirm:$false
Start-Sleep -Seconds 1

# ---------- 2. 替换二进制 ----------
# TSF DLL（weasel*.dll/.ime）可能仍被打开着文本框的应用进程占用。
# Windows 允许重命名被加载的 DLL：先把旧文件改名为 .old.<时间戳>，再放入新文件。
Step '替换二进制（被占用的 DLL 用改名法）'
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$files = @('weasel.dll','weasel.ime','weaselx64.dll','weaselx64.ime',
           'WeaselServer.exe','WeaselDeployer.exe','WeaselSetup.exe','rime.dll')
foreach ($f in $files) {
    $src = Join-Path $OutDir $f
    if (-not (Test-Path $src)) { Write-Warning "跳过（无产物）: $f"; continue }
    $dst = Join-Path $weaselRoot $f
    if (Test-Path $dst) {
        try {
            Copy-Item $src $dst -Force
        } catch {
            # 文件被占用：改名旧文件再复制
            $old = "$dst.old.$stamp"
            Rename-Item $dst $old -Force
            Copy-Item $src $dst -Force
        }
    } else {
        Copy-Item $src $dst -Force
    }
    Write-Host "    $f"
}
# 清理历史 .old 残留（未被占用的可删）
Get-ChildItem "$weaselRoot\*.old.*" -ErrorAction SilentlyContinue | ForEach-Object {
    try { Remove-Item $_.FullName -Force -Confirm:$false } catch {}
}

# ---------- 2.5 同步系统目录 TSF DLL（关键！） ----------
# 应用实际加载的是 WeaselSetup 装进 System32/SysWOW64 的 weasel.dll，
# 只替换安装目录等于没部署 TSF 客户端。直接复制（被占用用改名法），
# 不调 WeaselSetup /s——它会拉起进程树，Start-Process -Wait 会死等。
Step '同步 System32/SysWOW64 TSF DLL'
$sysPairs = @(
    @{ src = Join-Path $OutDir 'weaselx64.dll'; dst = "$env:WINDIR\System32\weasel.dll" },
    @{ src = Join-Path $OutDir 'weasel.dll';    dst = "$env:WINDIR\SysWOW64\weasel.dll" }
)
foreach ($pair in $sysPairs) {
    if ((Test-Path $pair.dst) -and
        (Get-FileHash $pair.src).Hash -eq (Get-FileHash $pair.dst).Hash) {
        Write-Host "    已最新: $($pair.dst)"; continue
    }
    try {
        Copy-Item $pair.src $pair.dst -Force
    } catch {
        Rename-Item $pair.dst "$($pair.dst).old.$stamp" -Force
        Copy-Item $pair.src $pair.dst -Force
    }
    Write-Host "    已更新: $($pair.dst)"
}
foreach ($sysdir in "$env:WINDIR\System32", "$env:WINDIR\SysWOW64") {
    Get-ChildItem "$sysdir\weasel*.old.*" -ErrorAction SilentlyContinue | ForEach-Object {
        try { Remove-Item $_.FullName -Force -Confirm:$false } catch {}
    }
}

# ---------- 3. 显示名兜底 ----------
Step '确认语言栏显示名'
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

# ---------- 4. 用新引擎重新编译词库 ----------
# rime.dll 升级后（0.17.4 附带版 → 1.17.0），让 librime 自检并重建 build 产物
Step '用新引擎重新部署词库（约 30 秒 - 2 分钟）'
$csharp = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class RimeDeployer2
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

    public static int Deploy(string weaselRoot, string sharedDataDir, string userDataDir, string logDir)
    {
        SetDllDirectory(weaselRoot);
        RimeTraits t = new RimeTraits();
        t.data_size = Marshal.SizeOf(typeof(RimeTraits)) - 4;
        t.shared_data_dir = U8(sharedDataDir);
        t.user_data_dir = U8(userDataDir);
        t.distribution_name = U8("大帅拼音");
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
$logDir = Join-Path $env:TEMP 'rime.dashuai-deploy'
New-Item -ItemType Directory -Force $logDir | Out-Null
$ret = [RimeDeployer2]::Deploy($weaselRoot, (Join-Path $weaselRoot 'data'), $RimeUser, $logDir)
Write-Host "    部署返回: $ret (1=已编译, 0=无需编译)"
if (-not (Test-Path (Join-Path $RimeUser 'build\wanxiang.table.bin'))) {
    throw '部署后缺少 build\wanxiang.table.bin'
}

# ---------- 5. 重启服务 ----------
Step '启动大帅拼音服务'
Start-Process -FilePath (Join-Path $weaselRoot 'WeaselServer.exe') | Out-Null
Start-Sleep -Seconds 2
$srv = Get-Process WeaselServer -ErrorAction SilentlyContinue
if (-not $srv) { throw 'WeaselServer 未能启动' }

# 验证版本资源
$vi = (Get-Item (Join-Path $weaselRoot 'WeaselServer.exe')).VersionInfo
Write-Host ''
Write-Host ("    ProductName: {0}" -f $vi.ProductName) -ForegroundColor Green
Write-Host ("    FileDescription: {0}" -f $vi.FileDescription) -ForegroundColor Green

Step '完成！托盘图标悬停应显示"大帅拼音"。'
Write-Host '  提示：已打开的应用里旧 TSF DLL 仍在内存中，重开应用或注销后全面生效。'
