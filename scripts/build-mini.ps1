# ============================================================
#  大帅拼音·极简 TSF 前端 - 构建脚本（cl 直编，x64）
#  产物: build-out\mini\DashuaiMini.dll
# ============================================================
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Src = Join-Path $RepoRoot 'src-mini'
$Out = Join-Path $RepoRoot 'build-out\mini'
$VsDevCmd = 'C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\Common7\Tools\VsDevCmd.bat'

New-Item -ItemType Directory -Force $Out | Out-Null

$line = "set NoDefaultCurrentDirectoryInExePath=&& " +
        "set `"PATH=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer;%PATH%`" && " +
        "set VSCMD_START_DIR=none && " +
        "call `"$VsDevCmd`" -arch=amd64 -no_logo && " +
        "cd /d `"$Src`" && " +
        "rc /nologo /fo mini.res mini.rc && " +
        "cl /nologo /LD /EHsc /std:c++17 /O2 /W3 /utf-8 /DUNICODE /D_UNICODE " +
        "dllmain.cpp TextService.cpp RimeEngine.cpp CandidateWindow.cpp mini.res " +
        "/Fe:`"$Out\DashuaiMini.dll`" " +
        "/link /DEF:DashuaiMini.def user32.lib gdi32.lib ole32.lib oleaut32.lib " +
        "advapi32.lib shell32.lib uuid.lib"
cmd /c $line
if ($LASTEXITCODE -ne 0) { throw "编译失败 (exit $LASTEXITCODE)" }

# 运行时依赖：rime.dll 与 DLL 同目录
Copy-Item (Join-Path $RepoRoot 'build-out\rime.dll') $Out -Force
Write-Host "==> 构建完成: $Out\DashuaiMini.dll" -ForegroundColor Green
