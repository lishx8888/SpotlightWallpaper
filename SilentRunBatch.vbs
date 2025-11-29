' 简单的静默执行批处理文件VBS脚本
Option Explicit
Dim shell, cmd, batchPath

' 设置默认PowerShell脚本路径
batchPath = "E:\github\SpotlightWallpaper\SpotlightAPIWallpaper.ps1"

' 检查是否提供了自定义批处理文件路径作为参数
If WScript.Arguments.Count > 0 Then
    batchPath = WScript.Arguments(0)
End If

' 创建Shell对象
Set shell = CreateObject("WScript.Shell")

' 使用PowerShell静默执行批处理文件（直接使用-File参数）
cmd = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoLogo -NoProfile -File """ & batchPath & """"

' 执行命令
shell.Run cmd, 0, True

' 清理对象
Set shell = Nothing