# Win7 普通用户双击即成功版（只保留最新一张壁纸，无需管理员）
$folder = "C:\Users\Administrator\Pictures\SpotlightWallpapers"
if(!(Test-Path $folder)){New-Item $folder -ItemType Directory -Force | Out-Null}

# 强制 TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 下载最新壁纸（固定文件名）
$url  = (Invoke-RestMethod https://api.qzink.me/spotlight).landscape_url
$file = "$folder\壁纸.jpg"

Invoke-WebRequest $url -OutFile $file -UseBasicParsing -TimeoutSec 30

# 删除文件夹中除当前壁纸外的所有文件
Get-ChildItem $folder -File | Where-Object {$_.FullName -ne $file} | Remove-Item -Force

# 直接用 API 设置壁纸（普通用户 100% 立刻生效）
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet=CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
[Wallpaper]::SystemParametersInfo(20, 0, $file, 3)

Write-Host "成功！最新壁纸已设为桌面（普通用户双击生效）" -ForegroundColor Green