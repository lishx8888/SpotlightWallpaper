# Windows Spotlight 壁纸下载器

一个专为Linux系统（特别是Armbian）设计的Windows Spotlight壁纸自动下载工具，支持SHA256去重功能，确保不会重复下载相同的壁纸。

## 功能特性

- ✅ 自动下载Windows Spotlight壁纸
- ✅ 使用SHA256哈希进行精确去重
- ✅ 智能缓存管理和格式迁移
- ✅ 完善的错误处理和日志记录
- ✅ 高度兼容性，特别优化支持Armbian系统
- ✅ 支持定时自动运行

## 系统要求

- **Linux系统**（特别优化支持Armbian）
- **依赖工具**：
  - curl (用于下载壁纸)
  - jq (用于JSON处理，可选但推荐)
  - sha256sum 或 openssl (用于计算SHA256哈希值)

## 安装步骤

### 在Armbian系统上安装

1. **更新系统并安装依赖**：
   ```bash
   sudo apt update && sudo apt install -y curl jq openssl
   ```

2. **克隆或下载项目**：
   ```bash
   git clone https://github.com/yourusername/SpotlightWallpaper.git
   cd SpotlightWallpaper
   ```
   或者直接下载脚本文件到您的工作目录。

3. **设置脚本权限**：
   ```bash
   chmod +x spotlight_wallpaper.sh
   chmod +x test_and_run_spotlight.sh
   ```

## 配置说明

### 脚本默认配置

- **壁纸保存目录**：`/mnt/disk/spot`
- **缓存文件路径**：`wallpaper_hash_cache.json`
- **API地址**：使用公共的Windows Spotlight壁纸API

### 自定义配置

您可以根据需要修改脚本中的以下变量：

```bash
# 编辑脚本
nano spotlight_wallpaper.sh

# 修改保存目录（找到并更改此行）
SAVE_FOLDER="/mnt/disk/spot"

# 您也可以修改日志文件路径
LOG_FILE="wallpaper_log.txt"
```

## 使用方法

### 手动运行

1. **基本运行**：
   ```bash
   ./spotlight_wallpaper.sh
   ```

2. **使用测试脚本验证功能**：
   ```bash
   ./test_and_run_spotlight.sh
   ```
   这个测试脚本会自动检查系统环境、依赖项、缓存文件，并运行主脚本进行测试。

### 设置定时任务

要让壁纸下载器定期自动运行，请设置crontab任务：

1. **编辑crontab**：
   ```bash
   crontab -e
   ```

2. **添加定时任务**（例如每小时运行一次）：
   ```bash
   0 * * * * cd /path/to/SpotlightWallpaper && ./spotlight_wallpaper.sh >> /path/to/SpotlightWallpaper/wallpaper_log.txt 2>&1
   ```
   请将`/path/to/SpotlightWallpaper`替换为实际的脚本路径。

3. **或者每天早上8点运行**：
   ```bash
   0 8 * * * cd /path/to/SpotlightWallpaper && ./spotlight_wallpaper.sh >> /path/to/SpotlightWallpaper/wallpaper_log.txt 2>&1
   ```

## 自动设置壁纸

如果您想让系统自动使用下载的壁纸作为桌面背景，可以使用以下方法：

### 使用feh设置壁纸（推荐）

1. **安装feh**：
   ```bash
   sudo apt install -y feh
   ```

2. **创建一个简单的设置壁纸脚本**：
   ```bash
   nano set_wallpaper.sh
   ```

3. **添加以下内容**：
   ```bash
   #!/bin/bash
   SAVE_FOLDER="/mnt/disk/spot"
   # 选择最新的壁纸设置为桌面背景
   feh --bg-scale $(ls -t $SAVE_FOLDER/*.jpg | head -n1)
   ```

4. **设置脚本权限**：
   ```bash
   chmod +x set_wallpaper.sh
   ```

5. **将其添加到启动项或定时任务**：
   ```bash
   # 添加到crontab，每小时更新一次壁纸
   0 * * * * /path/to/set_wallpaper.sh
   ```

## 故障排除

### 常见问题及解决方案

1. **下载失败**
   - 检查网络连接
   - 确认curl是否正确安装
   - 查看日志文件获取详细错误信息

2. **缓存文件错误**
   - 如果出现JSON解析错误，可以手动删除缓存文件：
     ```bash
     mv wallpaper_hash_cache.json wallpaper_hash_cache.json.bak
     ```
   - 下次运行脚本时会自动创建新的缓存文件

3. **权限问题**
   - 确保脚本有执行权限：`chmod +x spotlight_wallpaper.sh`
   - 确保保存目录有写入权限

4. **jq相关错误**
   - 如果遇到jq语法错误，确保jq版本兼容
   - 可以尝试更新jq：`sudo apt install --reinstall jq`

## 日志文件

脚本会输出日志信息到终端，同时也可以通过添加重定向到文件来保存日志：

```bash
./spotlight_wallpaper.sh >> wallpaper_log.txt 2>&1
```

查看日志文件可以帮助您诊断问题：

```bash
tail -f wallpaper_log.txt
```

## 缓存管理

- 缓存文件存储了已下载壁纸的哈希值，防止重复下载
- 如果需要清除缓存重新开始，可以执行：
  ```bash
  mv wallpaper_hash_cache.json wallpaper_hash_cache.json.old
  ```
- 脚本会自动处理旧缓存格式的迁移

## 关于SHA256去重功能

此版本使用SHA256哈希算法进行文件去重，相比传统的MD5更安全可靠。脚本会自动：

1. 为每个下载的壁纸计算SHA256哈希值
2. 将哈希值和文件信息存储在缓存中
3. 在下载新壁纸前检查是否已经存在
4. 自动迁移旧格式的缓存文件

## 贡献

欢迎提交Issue或Pull Request来改进这个项目！

## 许可证

[MIT](LICENSE)

---

**注意**：此工具仅用于个人学习和欣赏Windows Spotlight壁纸，请勿用于商业用途。壁纸版权归Microsoft所有。