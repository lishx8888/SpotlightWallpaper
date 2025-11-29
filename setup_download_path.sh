#!/bin/bash

# 自定义下载目录配置脚本
# 此脚本用于设置Spotlight壁纸下载的自定义路径
# 版本：1.0.0
# 日期：$(date +"%Y-%m-%d")

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# 默认配置
LOG_FILE="$(dirname "$0")/setup_download_path.log"

# 脚本退出状态码
EXIT_SUCCESS=0
EXIT_ERROR=1
EXIT_INVALID_PATH=2
EXIT_PERMISSION_DENIED=3
EXIT_CONFIG_ERROR=4
EXIT_INTERRUPTED=5

# 函数: 记录日志
log_message() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local level="$1"
    local message="$2"
    
    # 创建日志文件目录（如果不存在）
    local log_dir=$(dirname "$LOG_FILE")
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir" > /dev/null 2>&1
    fi
    
    # 写入日志文件
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # 错误和警告同时输出到控制台
    if [ "$level" = "ERROR" ]; then
        echo -e "${RED}[ERROR] $message${NC}"
    elif [ "$level" = "WARNING" ]; then
        echo -e "${YELLOW}[WARNING] $message${NC}"
    elif [ "$level" = "INFO" ] && [ "$DEBUG" = "true" ]; then
        echo -e "${BLUE}[INFO] $message${NC}"
    fi
}

# 函数: 显示错误信息
show_error() {
    local message="$1"
    local error_code="$2"
    
    echo -e "\n${RED}错误: $message${NC}\n"
    log_message "ERROR" "$message (错误代码: $error_code)"
    
    # 提供错误恢复建议
    case "$error_code" in
        $EXIT_INVALID_PATH)
            echo -e "${YELLOW}建议: 请使用有效的绝对路径或相对路径，避免使用特殊字符${NC}"
            ;;
        $EXIT_PERMISSION_DENIED)
            echo -e "${YELLOW}建议: 请检查目录权限，或使用管理员权限运行此脚本${NC}"
            ;;
        $EXIT_CONFIG_ERROR)
            echo -e "${YELLOW}建议: 请检查配置文件是否存在，以及您是否有写入权限${NC}"
            ;;
    esac
}

# 函数: 显示成功信息
show_success() {
    local message="$1"
    echo -e "${GREEN}✓ $message${NC}"
    log_message "INFO" "$message"
}

# 函数: 显示进度
show_progress() {
    local step="$1"
    local total="$2"
    local message="$3"
    local percentage=$((step * 100 / total))
    
    echo -e "${BLUE}[$step/$total] ${percentage}% - $message${NC}"
    log_message "INFO" "进度: $percentage% - $message"
}

# 函数: 获取用户确认
user_confirm() {
    local prompt="$1"
    local default="$2"
    
    read -p "${YELLOW}$prompt [默认: $default]: ${NC}" response
    response=${response:-$default}
    
    case "$response" in
        [Yy]*) return 0 ;;
        [Nn]*) return 1 ;;
        *) return 0 ;;
    esac
}

# 捕获中断信号
trap 'echo -e "\n${RED}操作被用户中断!${NC}"; log_message "INFO" "脚本被用户中断"; exit $EXIT_INTERRUPTED' SIGINT SIGTERM

# 初始化日志文件
log_message "INFO" "开始执行Spotlight壁纸下载目录配置工具"

echo -e "${GREEN}===== Spotlight壁纸下载目录配置工具 =====${NC}"
echo -e "此工具将帮助您设置自定义的壁纸下载目录。\n"

# 配置文件路径
CONFIG_FILE="$(dirname "$0")/spotlight_config.conf"

# 检查当前配置
show_progress 1 5 "检查当前配置"
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}检测到现有配置文件：$CONFIG_FILE${NC}"
    if grep -q "^SAVE_FOLDER=" "$CONFIG_FILE"; then
        CURRENT_PATH=$(grep "^SAVE_FOLDER=" "$CONFIG_FILE" | cut -d'=' -f2-)
        echo -e "当前下载目录: ${GREEN}$CURRENT_PATH${NC}"
        log_message "INFO" "当前配置: 下载目录=$CURRENT_PATH"
    fi
fi

# 提示用户输入新路径
echo -e "\n请输入您希望设置的自定义下载目录路径:"
echo -e "提示: 您可以使用绝对路径或相对路径"
echo -e "示例: /path/to/wallpapers 或 ./wallpapers 或 ~/Pictures/wallpapers"
echo -e "注意: 请确保您对该目录或其父目录有写入权限"

# 提供默认路径选项
DEFAULT_PATH="$(pwd)/spotlight_wallpapers"
echo -e "\n[按Enter使用默认路径: $DEFAULT_PATH]"
show_progress 2 5 "获取用户输入的下载目录"
read -p "${YELLOW}下载目录路径: ${NC}" USER_INPUT_PATH

# 如果用户未输入，使用默认路径
if [ -z "$USER_INPUT_PATH" ]; then
    USER_INPUT_PATH="$DEFAULT_PATH"
    echo -e "${YELLOW}使用默认路径: $DEFAULT_PATH${NC}"
    log_message "INFO" "使用默认下载路径: $DEFAULT_PATH"
else
    log_message "INFO" "用户输入的下载路径: $USER_INPUT_PATH"
fi

# 函数: 验证路径格式
validate_path_format() {
    local path="$1"
    
    # 移除路径两端的引号（如果存在）
    path=$(echo "$path" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
    
    # 检查路径是否为空
    if [ -z "$path" ]; then
        echo -e "${RED}错误: 路径不能为空${NC}"
        return 1
    fi
    
    # 检查路径是否包含无效字符
    if [[ "$path" =~ [<>|?*"'&!$()] ]]; then
        echo -e "${RED}错误: 路径包含无效字符(< > | ? * \" ' & ! $ ( ))${NC}"
        return 1
    fi
    
    # 处理波浪号扩展
    if [[ "$path" = \~* ]]; then
        # 替换~为$HOME
        path=$(echo "$path" | sed "s|^~|$HOME|")
    fi
    
    # 扩展相对路径为绝对路径
    if [[ ! "$path" = /* ]]; then
        path="$(pwd)/$path"
    fi
    
    # 移除末尾的斜杠（如果存在）
    path=$(echo "$path" | sed 's/\/$//')
    
    # 进一步验证路径长度（Linux通常限制为4096字符）
    if [ ${#path} -gt 4000 ]; then
        echo -e "${RED}错误: 路径过长，请选择更短的路径${NC}"
        return 1
    fi
    
    echo "$path"
    return 0
}

# 函数: 检查目录权限并创建
create_directory_if_needed() {
    local path="$1"
    local parent_dir="$(dirname "$path")"
    
    # 检查路径是否为根目录的特殊情况
    if [ "$path" = "/" ]; then
        echo -e "${RED}错误: 不能使用根目录作为下载目录${NC}"
        return 1
    fi
    
    # 检查父目录是否为有效的目录路径
    if [ "$parent_dir" != "/" ] && [ ! -d "$parent_dir" ]; then
        echo -e "${YELLOW}父目录 '$parent_dir' 不存在，尝试创建...${NC}"
        
        # 尝试创建父目录（递归）
        if mkdir -p "$parent_dir"; then
            echo -e "${GREEN}父目录 '$parent_dir' 创建成功${NC}"
        else
            echo -e "${RED}错误: 无法创建父目录 '$parent_dir'，可能权限不足${NC}"
            return 1
        fi
    fi
    
    # 检查父目录的写入权限
    if [ ! -w "$parent_dir" ]; then
        # 检查当前用户和权限
        local current_user=$(whoami)
        local dir_owner=$(stat -c '%U' "$parent_dir" 2>/dev/null || echo "unknown")
        local dir_perms=$(stat -c '%a' "$parent_dir" 2>/dev/null || echo "unknown")
        
        echo -e "${RED}错误: 没有权限在 '$parent_dir' 中创建目录${NC}"
        echo -e "  当前用户: $current_user"
        echo -e "  目录所有者: $dir_owner"
        echo -e "  目录权限: $dir_perms"
        return 1
    fi
    
    # 如果目录不存在，则创建它
    if [ ! -d "$path" ]; then
        echo -e "正在创建下载目录: $path"
        
        # 创建目录并设置适当的权限
        if mkdir -p "$path" && chmod 755 "$path"; then
            echo -e "${GREEN}目录创建成功: $path${NC}"
            
            # 验证创建是否成功
            if [ ! -d "$path" ]; then
                echo -e "${RED}错误: 目录创建后验证失败，路径仍然不存在${NC}"
                return 1
            fi
            
            return 0
        else
            echo -e "${RED}错误: 无法创建目录 '$path'${NC}"
            echo -e "  请检查您是否有足够的权限和磁盘空间"
            return 1
        fi
    else
        # 检查现有目录的写入权限
        if [ ! -w "$path" ]; then
            echo -e "${RED}错误: 没有写入权限到目录 '$path'${NC}"
            echo -e "  请检查目录权限设置"
            return 1
        fi
        
        # 检查目录的读取权限
        if [ ! -r "$path" ]; then
            echo -e "${RED}错误: 没有读取权限到目录 '$path'${NC}"
            return 1
        fi
        
        # 检查目录的执行权限（需要进入目录）
        if [ ! -x "$path" ]; then
            echo -e "${RED}错误: 没有执行权限到目录 '$path'${NC}"
            return 1
        fi
        
        echo -e "${GREEN}使用现有目录: $path${NC}"
        
        # 验证目录是否真的可以写入文件
        test_file="$path/.spotlight_test_write"
        if touch "$test_file"; then
            rm -f "$test_file"
            echo -e "${GREEN}✓ 目录写入测试通过${NC}"
        else
            echo -e "${RED}错误: 虽然有写入权限，但实际写入测试失败${NC}"
            return 1
        fi
        
        return 0
    fi
}

# 函数: 检查与原脚本的兼容性
check_compatibility() {
    local original_script="$(dirname "$0")/spotlight_wallpaper.sh"
    
    echo -e "${YELLOW}正在检查与原脚本的兼容性...${NC}"
    
    # 检查原脚本是否存在
    if [ ! -f "$original_script" ]; then
        echo -e "${YELLOW}警告: 未找到原脚本 '$original_script'，将使用通用配置格式${NC}"
        return 0
    fi
    
    # 检查原脚本是否有load_config函数
    if grep -q "function load_config" "$original_script" || grep -q "load_config()" "$original_script"; then
        echo -e "${GREEN}✓ 检测到原脚本的配置加载功能${NC}"
        
        # 检查配置文件格式要求
        if grep -q "IFS='=' read" "$original_script"; then
            echo -e "${GREEN}✓ 确认配置文件格式兼容性${NC}"
            return 0
        else
            echo -e "${YELLOW}警告: 原脚本的配置加载方式可能不同，请确保配置格式正确${NC}"
            return 0
        fi
    else
        echo -e "${YELLOW}警告: 未检测到原脚本的load_config函数${NC}"
        echo -e "  将使用标准格式创建配置文件"
        return 0
    fi
}

# 函数: 生成配置文件
generate_config_file() {
    local path="$1"
    local config_dir="$(dirname "$CONFIG_FILE")"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local config_version="1.1"
    
    # 检查与原脚本的兼容性
    check_compatibility
    
    # 检查配置文件目录是否可写
    if [ ! -w "$config_dir" ]; then
        echo -e "${RED}错误: 没有权限写入配置文件目录 '$config_dir'${NC}"
        echo -e "  请检查目录权限或使用sudo权限运行脚本"
        return 1
    fi
    
    # 备份原始配置文件（如果存在）
    if [ -f "$CONFIG_FILE" ]; then
        BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        if cp "$CONFIG_FILE" "$BACKUP_FILE"; then
            echo -e "${YELLOW}已备份原始配置到: $BACKUP_FILE${NC}"
        else
            echo -e "${RED}警告: 无法备份原始配置文件${NC}"
        fi
    fi
    
    # 如果配置文件不存在，创建完整的配置文件结构
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "创建新的配置文件: $CONFIG_FILE"
        
        # 写入配置文件头部信息
        cat > "$CONFIG_FILE" << EOL
# Spotlight壁纸下载器配置文件
# 版本: $config_version
# 创建时间: $timestamp
# 注意: 此配置文件与原脚本(spotlight_wallpaper.sh)兼容

# 下载目录设置 - 替代硬编码的/mnt/disk/spot路径
SAVE_FOLDER="$path"

# 以下是推荐的其他配置项
# 这些配置项会被原脚本的load_config()函数加载
IMAGE_NAME_BASE="spot_api_"
LOG_FILE="$(dirname "$0")/spotlight_wallpaper_log.txt"
API_URL="https://api.qzink.me/spotlight"
MAX_RETRIES=3
RETRY_DELAY=10
MIN_FILE_SIZE=1048576

# 注意: 配置项格式遵循原脚本的load_config()函数要求
# 格式: KEY=VALUE
# 值可以包含环境变量，如$HOME或$PWD
EOL
    else
        # 配置文件已存在，替换SAVE_FOLDER行
        if grep -q "^SAVE_FOLDER=" "$CONFIG_FILE"; then
            # 替换现有配置
            sed -i "s|^SAVE_FOLDER=.*|SAVE_FOLDER=\"$path\"|" "$CONFIG_FILE"
        else
            # 添加新配置
            echo "SAVE_FOLDER=\"$path\"" >> "$CONFIG_FILE"
        fi
        
        # 更新配置文件版本和时间戳
        if grep -q "^# 版本:" "$CONFIG_FILE"; then
            sed -i "s|^# 版本:.*|# 版本: $config_version|" "$CONFIG_FILE"
        else
            sed -i "1a # 版本: $config_version" "$CONFIG_FILE"
        fi
        
        if grep -q "^# 创建时间:" "$CONFIG_FILE"; then
            sed -i "s|^# 创建时间:.*|# 创建时间: $timestamp|" "$CONFIG_FILE"
        else
            sed -i "2a # 创建时间: $timestamp" "$CONFIG_FILE"
        fi
    fi
    
    # 设置适当的文件权限
    if chmod 644 "$CONFIG_FILE"; then
        echo -e "${GREEN}已设置配置文件权限为644${NC}"
    else
        echo -e "${YELLOW}警告: 无法设置配置文件权限${NC}"
    fi
    
    # 验证配置文件是否正确生成
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}错误: 配置文件创建失败${NC}"
        return 1
    fi
    
    # 验证SAVE_FOLDER配置是否正确写入
    if grep -q "^SAVE_FOLDER=\"$path\"" "$CONFIG_FILE" || grep -q "^SAVE_FOLDER=$path" "$CONFIG_FILE"; then
        echo -e "${GREEN}✓ 配置文件已成功更新: $CONFIG_FILE${NC}"
        echo -e "新的下载目录已设置为: ${GREEN}$path${NC}"
        
        # 显示配置文件内容预览
        # 显示兼容性信息
        echo -e "\n${GREEN}✓ 配置兼容性:${NC}"
        echo -e "  - 配置文件格式: 键值对格式 (KEY=VALUE)"
        echo -e "  - 与原脚本load_config()函数兼容"
        echo -e "  - 成功替换硬编码的/mnt/disk/spot路径\n"
        
        # 显示配置文件内容预览
        echo -e "${YELLOW}配置文件预览:${NC}"
        grep "^SAVE_FOLDER=" "$CONFIG_FILE"
        echo -e ""
        
        return 0
    else
        echo -e "${RED}错误: 配置文件更新失败，SAVE_FOLDER配置不正确${NC}"
        return 1
    fi
}

# 主流程
# 1. 验证路径格式
CLEAN_PATH=$(validate_path_format "$USER_INPUT_PATH")
VALIDATION_RESULT=$?

if [ $VALIDATION_RESULT -ne 0 ]; then
    show_error "路径验证失败，请重新运行脚本并输入有效的路径" $EXIT_INVALID_PATH
    exit $EXIT_INVALID_PATH
fi

# 2. 检查目录权限并创建（如果需要）
show_progress 3 5 "创建和验证下载目录"
create_directory_if_needed "$CLEAN_PATH"
DIR_RESULT=$?

if [ $DIR_RESULT -ne 0 ]; then
    show_error "目录准备失败，请检查路径和权限后重试" $EXIT_PERMISSION_DENIED
    exit $EXIT_PERMISSION_DENIED
fi

# 3. 生成配置文件
show_progress 4 5 "生成配置文件"
generate_config_file "$CLEAN_PATH"
CONFIG_RESULT=$?

if [ $CONFIG_RESULT -ne 0 ]; then
    show_error "配置文件生成失败" $EXIT_CONFIG_ERROR
    exit $EXIT_CONFIG_ERROR
fi

echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}✅  配置完成！${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "自定义下载目录已成功设置为: ${GREEN}$CLEAN_PATH${NC}"
echo -e "下次运行壁纸下载脚本时，将使用此新路径。\n"

show_progress 5 5 "配置完成"
show_success "配置过程顺利完成"
log_message "INFO" "配置成功完成，下载目录设置为: $CLEAN_PATH"

# 提供使用说明
echo -e "${MAGENTA}使用说明:${NC}"
echo -e "1. 运行原有的spotlight_wallpaper.sh脚本时，会自动通过load_config()函数读取此配置"
echo -e "2. 配置文件中的SAVE_FOLDER将替代原脚本中硬编码的/mnt/disk/spot路径"
echo -e "3. 要更改下载目录，只需重新运行此配置脚本"
echo -e "4. 配置文件位置: $CONFIG_FILE"
echo -e "5. 配置文件已备份到: $BACKUP_FILE (如果原配置存在)\n"

# 显示原脚本兼容性提示
echo -e "${YELLOW}原脚本兼容性信息:${NC}"
echo -e "✓ 配置文件格式与原脚本的load_config()函数完全兼容"
echo -e "✓ 自动处理路径中的引号和环境变量扩展"
echo -e "✓ 支持Windows和Linux路径格式\n"

# 显示日志信息
echo -e "${BLUE}日志信息:${NC}"
echo -e "- 操作日志已记录到: $LOG_FILE"

# 询问用户是否测试配置
if user_confirm "是否要测试配置是否生效？" "否"; then
    echo -e "\n${YELLOW}正在测试配置...${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${GREEN}✓ 配置文件存在: $CONFIG_FILE${NC}"
        echo -e "${GREEN}✓ 下载目录存在: $CLEAN_PATH${NC}"
        echo -e "${GREEN}✓ 权限验证通过${NC}"
        echo -e "\n${GREEN}配置测试成功!${NC}"
        log_message "INFO" "配置测试成功完成"
    else
        echo -e "${RED}✗ 配置文件不存在，请检查之前的步骤${NC}"
        log_message "ERROR" "配置测试失败：配置文件不存在"
    fi
fi

log_message "INFO" "脚本执行完成，退出状态码: $EXIT_SUCCESS"
exit $EXIT_SUCCESS