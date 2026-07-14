# ============================================================
#  大帅拼音输入法 - 源码构建脚本（阶段 1.5：品牌化 weasel 发行版）
#
#  流程：clone weasel 0.17.4 → 打品牌补丁 → 拉 librime SDK
#        → 下载/编译 boost → msbuild x64+Win32 → 产物收集到 build-out\
#
#  前置要求：VS2019 Build Tools（含 C++ 工具集 + ATL）、git、
#            已安装的小狼毫（借用其 7z.exe 与 data 目录）
#  兼容 Windows PowerShell 5.1（64 位）
# ============================================================
[CmdletBinding()]
param(
    # 跳过 boost 编译（已编译过时使用）
    [switch]$SkipBoost
)

$ErrorActionPreference = 'Stop'

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$SrcDir     = Join-Path $RepoRoot 'src'
$WeaselSrc  = Join-Path $SrcDir 'weasel'
$PatchFile  = Join-Path $RepoRoot 'patches\dashuai-branding.patch'
$OutDir     = Join-Path $RepoRoot 'build-out'
$WeaselTag  = '0.17.4'
$BoostVer   = '1.84.0'
$BoostDirName = 'boost_' + ($BoostVer -replace '\.', '_')

$VsDevCmd   = 'C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\Common7\Tools\VsDevCmd.bat'
$SevenZip   = 'C:\Program Files\Rime\weasel-0.17.4\7z.exe'
$InstalledData = 'C:\Program Files\Rime\weasel-0.17.4\data'

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

# 在 VS 开发环境中执行命令。三个环境坑的修复：
# 1. 清 NoDefaultCurrentDirectoryInExePath：weasel 的 bat 全用裸相对调用（call env.bat / b2），
#    该加固开启时会全部 "not recognized"
# 2. vswhere 所在 Installer 目录进 PATH（VsDevCmd 依赖）
# 3. VSCMD_START_DIR=none：阻止 VsDevCmd 改工作目录
function Invoke-DevCmd($workDir, $command) {
    $line = "set NoDefaultCurrentDirectoryInExePath=&& " +
            "set `"PATH=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer;%PATH%`" && " +
            "set VSCMD_START_DIR=none && " +
            "call `"$VsDevCmd`" -arch=amd64 -no_logo && " +
            "cd /d `"$workDir`" && $command"
    # cmd 输出必须流向控制台而非函数返回值，否则 $ret 被 stdout 污染成数组
    cmd /c $line | Out-Host
    return $LASTEXITCODE
}

# ---------- 0. 前置检查 ----------
if (-not (Test-Path $VsDevCmd)) { throw "未找到 VS2019 Build Tools: $VsDevCmd" }
$atl = Get-ChildItem 'C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\*\atlmfc\include\atlbase.h' -ErrorAction SilentlyContinue
if (-not $atl) { throw '缺少 ATL 组件：VS Installer 追加 Microsoft.VisualStudio.Component.VC.ATL' }
if (-not (Test-Path $SevenZip)) { throw "未找到 7z.exe（依赖已安装的小狼毫）: $SevenZip" }

# ---------- 1. 源码 ----------
Step "获取 weasel $WeaselTag 源码"
New-Item -ItemType Directory -Force $SrcDir | Out-Null
if (-not (Test-Path (Join-Path $WeaselSrc 'weasel.sln'))) {
    git clone --branch $WeaselTag --depth 1 https://github.com/rime/weasel.git $WeaselSrc
    if ($LASTEXITCODE -ne 0) { throw 'git clone 失败' }
} else { Write-Host '    已存在，跳过 clone' }

# ---------- 2. 品牌补丁 ----------
Step '应用大帅拼音品牌补丁'
Push-Location $WeaselSrc
$dirty = git status --porcelain -- include/WeaselUtility.h
if ($dirty) {
    Write-Host '    源码树已打过补丁，跳过'
} else {
    git apply --binary $PatchFile
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'git apply 补丁失败' }
}
Pop-Location

# ---------- 3. librime SDK（官方预编译，含 lua/octagram/predict 插件） ----------
Step '获取 librime SDK'
if (-not (Test-Path (Join-Path $WeaselSrc 'lib64\rime.lib'))) {
    powershell -NoProfile -ExecutionPolicy Bypass -Command `
        "& { `$env:Path = '$(Split-Path $SevenZip);' + `$env:Path; Set-Location '$WeaselSrc'; .\get-rime.ps1 -use dev }"
    if (-not (Test-Path (Join-Path $WeaselSrc 'lib64\rime.lib'))) { throw 'get-rime.ps1 未产出 lib64\rime.lib' }
} else { Write-Host '    已存在，跳过' }

# ---------- 4. boost ----------
$boostRoot = Join-Path $WeaselSrc "deps\$BoostDirName"
if (-not $SkipBoost) {
    Step "准备 boost $BoostVer"
    $boost7z = Join-Path $WeaselSrc "deps\$BoostDirName.7z"
    if (-not (Test-Path (Join-Path $boostRoot 'boost'))) {
        if (-not (Test-Path $boost7z)) {
            & curl.exe -L --retry 3 -sS -o $boost7z "https://archives.boost.io/release/$BoostVer/source/$BoostDirName.7z"
            if ($LASTEXITCODE -ne 0) { throw 'boost 下载失败' }
        }
        & $SevenZip x $boost7z "-o$(Join-Path $WeaselSrc 'deps')" -y | Out-Null
    }
    Step '编译 boost 静态库（x86 + x64，首次约 20-40 分钟）'
    # env.vs2019.bat 默认 BOOST_ROOT 指向 1_78_0，必须显式覆盖为实际版本
    $ret = Invoke-DevCmd $WeaselSrc "set BOOST_ROOT=$boostRoot&& call build.bat boost"
    if ($ret -ne 0) { throw "boost 编译失败（exit $ret），日志见控制台输出" }
}

# ---------- 5. 预置 data（跳过 build.bat 的 plum/bash 依赖） ----------
Step '预置 output\data'
New-Item -ItemType Directory -Force (Join-Path $WeaselSrc 'output\data') | Out-Null
Copy-Item "$InstalledData\*" (Join-Path $WeaselSrc 'output\data\') -Recurse -Force

# ---------- 6. 编译 weasel（x64 + Win32） ----------
Step '编译大帅拼音（msbuild x64 + Win32）'
Copy-Item (Join-Path $WeaselSrc 'env.vs2019.bat') (Join-Path $WeaselSrc 'env.bat') -Force
$ret = Invoke-DevCmd $WeaselSrc "set RELEASE_BUILD=1&& set BOOST_ROOT=$boostRoot&& call build.bat weasel"
if ($ret -ne 0) { throw "weasel 编译失败（exit $ret）" }

# ---------- 7. 产物收集 ----------
Step '收集产物到 build-out\'
New-Item -ItemType Directory -Force $OutDir | Out-Null
$artifacts = @('weasel.dll','weasel.ime','weaselx64.dll','weaselx64.ime',
               'WeaselServer.exe','WeaselDeployer.exe','WeaselSetup.exe','rime.dll')
foreach ($a in $artifacts) {
    $p = Join-Path $WeaselSrc "output\$a"
    if (Test-Path $p) { Copy-Item $p $OutDir -Force; Write-Host "    $a" }
    else { Write-Warning "缺产物: $a" }
}
# Win32 版 rime.dll 单独放（仅 32 位系统需要）
if (Test-Path (Join-Path $WeaselSrc 'output\Win32\rime.dll')) {
    New-Item -ItemType Directory -Force (Join-Path $OutDir 'Win32') | Out-Null
    Copy-Item (Join-Path $WeaselSrc 'output\Win32\rime.dll') (Join-Path $OutDir 'Win32\') -Force
}

Step '构建完成！产物在 build-out\，用 scripts\deploy-dashuai.ps1 部署到本机'
