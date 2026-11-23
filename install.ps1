#Requires -Version 5.1
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Info($m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[+] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "[-] $m" -ForegroundColor Red }

Write-Host ""
Write-Host "LiteLoaderQQNT installer for QQNT 9.9.37+ (Electron 40 / Node 24)" -ForegroundColor Magenta
Write-Host ""

# ---- 0. QQ must be closed -------------------------------------------------
if (Get-Process QQ -ErrorAction SilentlyContinue) {
    Fail "QQ 正在运行，请先完全退出 QQ（含托盘图标）后重新运行本脚本。"
    exit 1
}

# ---- 1. locate QQ root ----------------------------------------------------
$candidates = @(
    (Join-Path $env:ProgramFiles "Tencent\QQNT"),
    (Join-Path ${env:ProgramFiles(x86)} "Tencent\QQNT"),
    (Join-Path $env:LOCALAPPDATA "Programs\QQNT")
)
$qqRoot = $null
foreach ($c in $candidates) {
    if ($c -and (Test-Path (Join-Path $c "QQ.exe"))) { $qqRoot = $c; break }
}
if (-not $qqRoot) {
    Fail "未找到 QQNT 安装目录（已尝试 Program Files / Program Files (x86) / LocalAppData）。"
    exit 1
}
Info "QQ 目录: $qqRoot"

# ---- 2. resolve active version -------------------------------------------
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
$dll    = Join-Path $verDir "QQNT.dll"

Info "版本目录: $verDir"
if (-not (Test-Path $dll))  { Fail "QQNT.dll 不存在: $dll"; exit 1 }
if (-not (Test-Path $pkg))  { Fail "package.json 不存在: $pkg"; exit 1 }

# ---- 3. write permission check -------------------------------------------
$probe = Join-Path $verDir ".llqqnt_write_test"
try {
    [System.IO.File]::WriteAllText($probe, "1")
    Remove-Item $probe -Force
} catch {
    Fail "没有写入权限。请右键以管理员身份运行 install.bat。"
    exit 1
}

# ---- 4. signature check on QQNT.dll --------------------------------------
if (-not ("QQNTSig" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.IO;
public static class QQNTSig {
    static readonly byte[] Pat = { 0x48,0x89,0xCE,0x48,0x8B,0x11,0x4C,0x8B,0x41,0x08,0x49,0x29,0xD0,0x48,0x8B,0x49,0x18,0xE8 };
    public static bool Find(string path) {
        using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20)) {
            int chunk = 1 << 22;
            byte[] buf = new byte[chunk + Pat.Length];
            int carry = 0;
            while (true) {
                int read = fs.Read(buf, carry, chunk);
                if (read <= 0) break;
                int total = carry + read;
                int limit = total - Pat.Length;
                for (int i = 0; i <= limit; i++) {
                    int j = 0;
                    while (j < Pat.Length && buf[i + j] == Pat[j]) j++;
                    if (j == Pat.Length) return true;
                }
                carry = Pat.Length - 1;
                Buffer.BlockCopy(buf, total - carry, buf, 0, carry);
            }
        }
        return false;
    }
}
"@
}
Ok "QQNT.dll 存在校验特征码（9.9.37 系列）"
if (-not [QQNTSig]::Find($dll)) {
    Warn "QQNT.dll 中未找到已知校验特征码。此 QQ 版本可能尚未适配，安装后可能无法启动。"
    $answer = Read-Host "仍要继续？(y/N)"
    if ($answer -notmatch '^(y|Y)$') { exit 1 }
}

# ---- 5. backup package.json ----------------------------------------------
$bak = "$pkg.llqqnt.bak"
if (-not (Test-Path $bak)) {
    Copy-Item $pkg $bak -Force
    Ok "已备份 package.json -> package.json.llqqnt.bak"
} else {
    Info "备份已存在: $bak"
}

# ---- 6. deploy LiteLoaderQQNT --------------------------------------------
$llSrc = Join-Path $here "LiteLoaderQQNT"
$llDst = Join-Path $appDir "LiteLoaderQQNT"
if (-not (Test-Path (Join-Path $llSrc "src\main.js"))) {
    Fail "安装包缺少 LiteLoaderQQNT 目录，请确认解压完整。"
    exit 1
}
if (Test-Path $llDst) {
    Remove-Item $llDst -Recurse -Force
}
Copy-Item $llSrc $llDst -Recurse -Force
Ok "已部署 LiteLoaderQQNT -> $llDst"

# ---- 7. rewrite package.json main ----------------------------------------
$pkgObj = Get-Content $pkg -Raw -Encoding UTF8 | ConvertFrom-Json
$pkgObj.main = "./LiteLoaderQQNT/src/main.js"
$json = $pkgObj | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($pkg, $json, (New-Object System.Text.UTF8Encoding($false)))
Ok "package.json main -> ./LiteLoaderQQNT/src/main.js"

# ---- 8. deploy version.dll ----------------------------------------------
$dllSrc = Join-Path $here "version.dll"
if (-not (Test-Path $dllSrc)) { Fail "安装包缺少 version.dll"; exit 1 }
$dllDst = Join-Path $verDir "version.dll"
Copy-Item $dllSrc $dllDst -Force
Ok "已部署 version.dll -> $dllDst"

Write-Host ""
Ok "安装完成。启动 QQ 即可。"
Write-Host ""
Write-Host "  日志: %LOCALAPPDATA%\LiteLoaderQQNT\patch.log" -ForegroundColor DarkGray
Write-Host "  插件: $llDst\plugins" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  注意: QQ 自动更新后会切换版本目录，需要重新运行本脚本。" -ForegroundColor Yellow
Write-Host ""
