#Requires -Version 5.1
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Info($m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[+] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "[-] $m" -ForegroundColor Red }

Write-Host ""
Write-Host "LiteLoaderQQNT uninstaller" -ForegroundColor Magenta
Write-Host ""

if (Get-Process QQ -ErrorAction SilentlyContinue) {
    Fail "QQ 正在运行，请先完全退出 QQ 后重新运行。"
    exit 1
}

$candidates = @(
    (Join-Path $env:ProgramFiles "Tencent\QQNT"),
    (Join-Path ${env:ProgramFiles(x86)} "Tencent\QQNT"),
    (Join-Path $env:LOCALAPPDATA "Programs\QQNT")
)
$qqRoot = $null
foreach ($c in $candidates) {
    if ($c -and (Test-Path (Join-Path $c "QQ.exe"))) { $qqRoot = $c; break }
}
if (-not $qqRoot) { Fail "未找到 QQNT 安装目录。"; exit 1 }

$versionsRoot = Join-Path $qqRoot "versions"
$cfgPath = Join-Path $versionsRoot "config.json"
$ver = $null
if (Test-Path $cfgPath) {
    try { $ver = (Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json).curVersion } catch {}
}
if (-not $ver) {
    $latest = Get-ChildItem $versionsRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if ($latest) { $ver = $latest.Name }
}
if (-not $ver) { Fail "无法确定当前 QQ 版本目录。"; exit 1 }

$verDir = Join-Path $versionsRoot $ver
$appDir = Join-Path $verDir "resources\app"
$pkg    = Join-Path $appDir "package.json"
$bak    = "$pkg.llqqnt.bak"

Info "版本目录: $verDir"

# restore package.json only when it still points at LiteLoader
if (Test-Path $pkg) {
    try {
        $pkgObj = Get-Content $pkg -Raw -Encoding UTF8 | ConvertFrom-Json
        $curMain = [string]$pkgObj.main
        if ($curMain -like "*LiteLoaderQQNT*") {
            if (Test-Path $bak) {
                Copy-Item $bak $pkg -Force
                Ok "已恢复 package.json（来自备份）"
            } else {
                $pkgObj.main = "./application.asar/app_launcher/index.js"
                $json = $pkgObj | ConvertTo-Json -Depth 20
                [System.IO.File]::WriteAllText($pkg, $json, (New-Object System.Text.UTF8Encoding($false)))
                Ok "已恢复 package.json.main -> ./application.asar/app_launcher/index.js"
            }
        } else {
            Info "package.json 未指向 LiteLoaderQQNT，跳过恢复（可能已被 QQ 更新覆盖）"
        }
    } catch {
        Warn "解析 package.json 失败，跳过恢复: $($_.Exception.Message)"
    }
}

# remove injected dll
$dll = Join-Path $verDir "version.dll"
if (Test-Path $dll) {
    Remove-Item $dll -Force
    Ok "已移除 version.dll"
} else {
    Info "version.dll 不存在，跳过"
}

# retire LiteLoader folder (keep plugins/data for the user)
$llDst = Join-Path $appDir "LiteLoaderQQNT"
if (Test-Path $llDst) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $moved = "$llDst.uninstalled-$stamp"
    Move-Item $llDst $moved
    Ok "已移动 LiteLoaderQQNT -> $moved（插件与配置保留）"
} else {
    Info "LiteLoaderQQNT 目录不存在，跳过"
}

Write-Host ""
Ok "卸载完成。"
Write-Host ""
