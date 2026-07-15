# ============================================================
#  大帅拼音输入法 - 完整安装包构建
#  组装共享数据负载（万象方案+词库+lua+预编译词库+语言模型）→ NSIS 打包
#  前置：build-dashuai.ps1 已产出二进制；本机已部署万象（%APPDATA%\Rime）
#  用法：.\make-installer.ps1            # 组装 + 打包
#        .\make-installer.ps1 -DataOnly # 只组装数据负载（供隔离验证）
# ============================================================
[CmdletBinding()]
param([switch]$DataOnly)

$ErrorActionPreference = 'Stop'

$RepoRoot  = Split-Path -Parent $PSScriptRoot
$WeaselSrc = Join-Path $RepoRoot 'src\weasel'
$DataDir   = Join-Path $WeaselSrc 'output\data'
$RimeUser  = Join-Path $env:APPDATA 'Rime'
$OutDir    = Join-Path $RepoRoot 'build-out'
$MakeNsis  = "${env:ProgramFiles(x86)}\NSIS\makensis.exe"

$WEASEL_VERSION  = '0.17.4'
$WEASEL_BUILD    = '1'
$PRODUCT_VERSION = '0.17.4.1'

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

if (-not (Test-Path (Join-Path $WeaselSrc 'output\weaselx64.dll'))) { throw '缺二进制，先跑 build-dashuai.ps1' }
if (-not (Test-Path (Join-Path $RimeUser 'build\wanxiang.table.bin'))) { throw '本机万象未部署，无从取数据' }

# ---------- 1. 剔除原版预设方案（大帅拼音只发布万象，极简） ----------
Step '清理共享数据中的原版方案'
$stockPatterns = 'bopomofo*.yaml','cangjie5*.yaml','cangjie5.dict.yaml','luna_*.yaml',
                 'stroke.dict.yaml','stroke.schema.yaml','terra_pinyin*.yaml',
                 'zhuyin.yaml','pinyin.yaml','essay.txt'
foreach ($p in $stockPatterns) {
    Get-ChildItem (Join-Path $DataDir $p) -ErrorAction SilentlyContinue |
        Remove-Item -Force -Confirm:$false
}

# ---------- 2. 万象配置/方案/大帅定制 ----------
Step '注入万象配置与大帅定制'
$topFiles = 'default.yaml','weasel.yaml','custom_phrase.txt',
            'wanxiang.schema.yaml','wanxiang.dict.yaml','wanxiang.custom.yaml',
            'wanxiang_algebra.yaml','wanxiang_symbols.yaml',
            'wanxiang_english.dict.yaml','wanxiang_english.schema.yaml',
            'wanxiang_mixedcode.dict.yaml','wanxiang_mixedcode.schema.yaml',
            'wanxiang_reverse.dict.yaml','wanxiang_reverse.schema.yaml'
foreach ($f in $topFiles) { Copy-Item (Join-Path $RimeUser $f) $DataDir -Force }

# ---------- 3. 词库源 / lua / 预编译词库 ----------
Step '同步 dicts / lua / build（预编译免新机首次等待）'
& robocopy "$RimeUser\dicts" "$DataDir\dicts" /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy dicts 失败 ($LASTEXITCODE)" }
& robocopy "$RimeUser\lua" "$DataDir\lua" /MIR /R:1 /W:1 /XD '*.userdb' /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy lua 失败 ($LASTEXITCODE)" }
# 白名单同步：本机 build 里可能残留原始小狼毫的朙月/仓颉等废产物，只带万象相关
& robocopy "$RimeUser\build" "$DataDir\build" 'wanxiang*' 'default.yaml' 'weasel.yaml' /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy build 失败 ($LASTEXITCODE)" }
# robocopy 文件过滤不清除目标端多余文件，显式剔除白名单之外的
Get-ChildItem "$DataDir\build" |
    Where-Object { $_.Name -notlike 'wanxiang*' -and $_.Name -notin 'default.yaml','weasel.yaml' } |
    Remove-Item -Force -Confirm:$false
$global:LASTEXITCODE = 0

# ---------- 4. 语言模型（400MB，硬链接零拷贝） ----------
Step '放置语言模型'
$gram = Join-Path $DataDir 'wanxiang-lts-zh-hans.gram'
if (-not (Test-Path $gram)) {
    try { New-Item -ItemType HardLink -Path $gram -Target (Join-Path $RimeUser 'wanxiang-lts-zh-hans.gram') | Out-Null }
    catch { Copy-Item (Join-Path $RimeUser 'wanxiang-lts-zh-hans.gram') $gram }
}

if ($DataOnly) { Step '数据负载组装完成（-DataOnly，未打包）'; return }

# ---------- 5. NSIS 打包 ----------
Step 'makensis 打包（负载约 630MB，压缩需数分钟）'
& $MakeNsis /DWEASEL_VERSION=$WEASEL_VERSION /DWEASEL_BUILD=$WEASEL_BUILD `
    /DPRODUCT_VERSION=$PRODUCT_VERSION (Join-Path $WeaselSrc 'output\install.nsi') | Out-Host
if ($LASTEXITCODE -ne 0) { throw "makensis 失败 ($LASTEXITCODE)" }

# ---------- 6. 收集（统一发布命名：平台标识入文件名） ----------
$exe = Join-Path $WeaselSrc "output\archives\dashuai-pinyin-$PRODUCT_VERSION-installer.exe"
$released = "dashuai-pinyin-$PRODUCT_VERSION-windows-x64-setup.exe"
Copy-Item $exe (Join-Path $OutDir $released) -Force
Step ("完成: build-out\$released ({0:N0} MB)" -f ((Get-Item $exe).Length/1MB))
