# Win7 普通用户双击即成功版（Windows Spotlight 最新壁纸 + 强力刷新）
$folder = "$env:USERPROFILE\Pictures\SpotlightWallpapers"
if(!(Test-Path $folder)){New-Item $folder -ItemType Directory -Force | Out-Null}

# 强制 TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 下载最新横版壁纸
$url = (Invoke-RestMethod https://api.qzink.me/spotlight).landscape_url
$original = "$folder\Spotlight壁纸.jpg"

Invoke-WebRequest $url -OutFile $original -UseBasicParsing -TimeoutSec 30

# 删除旧文件（只保留最新一张）
Get-ChildItem $folder -File | Where-Object {$_.FullName -ne $original} | Remove-Item -Force

# 设置壁纸样式为“填充”
$regPath = "HKCU:\Control Panel\Desktop"
Set-ItemProperty -Path $regPath -Name "WallpaperStyle" -Value "10"  # 填充
Set-ItemProperty -Path $regPath -Name "TileWallpaper"  -Value "0"

# API 设置壁纸
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@

$result = [Wallpaper]::SystemParametersInfo(20, 0, $original, 3)

if ($result -eq 0) {
    Write-Host "API 设置失败！请右键脚本 → 以管理员身份运行一次" -ForegroundColor Red
} else {
    Write-Host "API 调用成功，正在强力刷新桌面..." -ForegroundColor Yellow

    # 相同的强力刷新机制
    Start-Sleep -Seconds 1
    1..15 | ForEach-Object {
        Start-Process "rundll32.exe" -ArgumentList "user32.dll,UpdatePerUserSystemParameters" -WindowStyle Hidden
        Start-Sleep -Milliseconds 300
    }

    Write-Host "成功！最新 Spotlight 壁纸已设为桌面" -ForegroundColor Green
}