# Win7 普通用户静默最高清晰度版（修复刷新 + Win7 扩展名）
$folder = "$env:USERPROFILE\Pictures\SpotlightWallpapers"  # 自动当前用户路径
if(!(Test-Path $folder)){New-Item $folder -ItemType Directory -Force | Out-Null}

# 强制 TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 下载最新壁纸
$url  = (Invoke-RestMethod https://api.qzink.me/spotlight).landscape_url
$original = "$folder\最新壁纸.jpg"

try {
    Invoke-WebRequest $url -OutFile $original -UseBasicParsing -TimeoutSec 30
} catch {
    Write-Host "下载失败: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# 删除旧文件（只保留最新）
Get-ChildItem $folder -File | Where-Object {$_.FullName -ne $original} | Remove-Item -Force

# 设置壁纸样式为“填充”（最锐利）
$regPath = "HKCU:\Control Panel\Desktop"
Set-ItemProperty -Path $regPath -Name "WallpaperStyle" -Value "10"  # 填充（Fill）
Set-ItemProperty -Path $regPath -Name "TileWallpaper"  -Value "0"

# 直接替换系统缓存（Win7 用 .jpg 扩展）
$cachePath = "$env:APPDATA\Microsoft\Windows\Themes"
$transcoded = "$cachePath\TranscodedWallpaper.jpg"  # Win7 标准扩展

# 备份旧缓存（可选）
if (Test-Path $transcoded) { 
    Copy-Item $transcoded "$cachePath\TranscodedWallpaper.bak" -Force 
    Remove-Item $transcoded -Force  # 先删旧的
}

# 复制原图到缓存（最高质量）
Copy-Item $original $transcoded -Force

# 双重刷新：API + Rundll32（确保立即生效）
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Refresh {
    [DllImport("user32.dll")]
    public static extern int SystemParametersInfo(int uAction, int uParam, int lpvParam, int fuWinIni);
}
"@
# API 刷新（SPI_SETDESKWALLPAPER 后强制更新）
[Refresh]::SystemParametersInfo(0x0014, 0, 0, 0x01 -bor 0x02)  # 刷新参数
[Refresh]::SystemParametersInfo(20, 0, 0, 3)  # 广播变化

# Rundll32 兜底（Win7 可靠命令）
Start-Sleep -Milliseconds 500  # 稍等复制完成
Start-Process "rundll32.exe" -ArgumentList "user32.dll,UpdatePerUserSystemParameters" -WindowStyle Hidden -Wait

Write-Host "成功！最新 Spotlight 壁纸已静默替换缓存并刷新（立即生效，最高清晰度）" -ForegroundColor Green