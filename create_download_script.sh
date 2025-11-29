#!/bin/bash

# 目录设置和脚本生成工具
# 此脚本用于设置自定义壁纸下载目录并生成对应的下载脚本
# 版本：1.0.0

# 版本信息
SCRIPT_VERSION="1.0.0"

# 定义输出颜色
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
PURPLE="\033[0;35m"
CYAN="\033[0;36m"
NC="\033[0m" # 无颜色

# 日志配置
LOG_LEVEL="INFO" # 可选: DEBUG, INFO, WARNING, ERROR
LOG_FILE="$(dirname "$0")/create_download_script.log"

# 定义常量
GENERATED_SCRIPT="custom_spotlight_wallpaper.sh"

# 定义退出状态码
EXIT_SUCCESS=0
EXIT_ERROR=1
EXIT_INVALID_PATH=2
EXIT_PERMISSION_DENIED=3
EXIT_SCRIPT_ERROR=4
EXIT_INTERRUPTED=5
EXIT_USER_ABORT=6
EXIT_CONFIG_ERROR=7
EXIT_RESOURCE_NOT_AVAILABLE=8
EXIT_SCRIPT_GENERATION_FAILED=9

# 中断信号处理
interrupt_handler() {
    echo -e "\n${RED}\n=======================================${NC}"
    echo -e "${RED}❌ 脚本被用户中断!${NC}"
    echo -e "${RED}=======================================${NC}"
    log_message "ERROR" "脚本被用户中断 (SIGINT/SIGTERM)"
    exit $EXIT_INTERRUPTED
}

# 设置信号处理
trap interrupt_handler SIGINT SIGTERM

# 显示欢迎信息
show_welcome() {
    echo -e "${GREEN}===== Spotlight壁纸下载脚本生成工具 =====${NC}"
    echo -e "此工具将帮助您设置自定义的壁纸下载目录并生成对应的下载脚本。\n"
}

# 日志记录函数（增强版）
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local log_dir=$(dirname "$LOG_FILE")
    
    # 确保日志目录存在
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir" 2>/dev/null || true
    fi
    
    # 日志级别优先级: ERROR > WARNING > INFO > DEBUG
    local level_priority
    case $level in
        "ERROR") level_priority=4 ;;
        "WARNING") level_priority=3 ;;
        "INFO") level_priority=2 ;;
        "DEBUG") level_priority=1 ;;
        *) level_priority=2 ;;
    esac
    
    local log_level_priority
    case $LOG_LEVEL in
        "ERROR") log_level_priority=4 ;;
        "WARNING") log_level_priority=3 ;;
        "INFO") log_level_priority=2 ;;
        "DEBUG") log_level_priority=1 ;;
        *) log_level_priority=2 ;;
    esac
    
    # 根据日志级别决定是否记录
    if [ $level_priority -lt $log_level_priority ]; then
        return
    fi
    
    # 输出到日志文件
    { 
        echo "[$timestamp] [$level] $message" 
    } >> "$LOG_FILE" 2>/dev/null || true
    
    # 输出到控制台（根据级别和设置）
    case $level in
        "ERROR")
            echo -e "${RED}❌ [$level] $message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠️  [$level] $message${NC}"
            ;;
        "INFO")
            if [ $log_level_priority -le 2 ]; then
                echo -e "${BLUE}ℹ️  $message${NC}"
            fi
            ;;
        "DEBUG")
            if [ $log_level_priority -le 1 ]; then
                echo -e "${CYAN}🐛 $message${NC}"
            fi
            ;;
    esac
}

# 显示成功信息
success_message() {
    local message="$1"
    echo -e "${GREEN}✓ $message${NC}"
}

# 显示错误信息
error_message() {
    local message="$1"
    echo -e "${RED}❌ $message${NC}"
}

# 显示警告信息
warning_message() {
    local message="$1"
    echo -e "${YELLOW}⚠️  $message${NC}"
}

# 显示信息（不带图标）
info_message() {
    local message="$1"
    echo -e "${BLUE}ℹ️  $message${NC}"
}

# 显示进度条
show_progress() {
    local current="$1"
    local total="$2"
    local width=50
    local percent=$((current * 100 / total))
    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    
    # 构建进度条
    local bar="${GREEN}"
    for ((i=0; i<filled; i++)); do
        bar="$bar█"
    done
    bar="$bar${YELLOW}"
    for ((i=0; i<empty; i++)); do
        bar="$bar░"
    done
    bar="$bar${NC}"
    
    # 输出进度条，使用回车符替换当前行
    echo -ne "\r[$bar] ${CYAN}${percent}%${NC} (${current}/${total})"
    
    # 完成时换行
    if [ $current -eq $total ]; then
        echo ""
    fi
}

# 用户确认函数
user_confirm() {
    local prompt="$1"
    local default=${2:-"n"} # 默认不确认
    
    local confirm
    read -p "${YELLOW}$prompt [y/N]: ${NC}" confirm
    
    # 如果未输入，使用默认值
    if [ -z "$confirm" ]; then
        confirm=$default
    fi
    
    # 转换为小写
    confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
    
    # 只接受y/yes作为确认
    if [[ "$confirm" == "y" || "$confirm" == "yes" ]]; then
        return 0
    else
        return 1
    fi
}

# 测试配置和环境
test_environment() {
    log_message "INFO" "开始环境检查"
    echo -e "\n${BLUE}===== 环境检查 =====${NC}"
    
    # 检查必要的命令
    local required_cmds=("bash" "mkdir" "chmod" "grep" "sed" "tail" "date" "whoami")
    local missing_cmds=()
    
    # 显示进度
    echo -e "${BLUE}检查必要命令...${NC}"
    
    local i=0
    for cmd in "${required_cmds[@]}"; do
        i=$((i + 1))
        show_progress $i ${#required_cmds[@]}
        
        if ! command -v "$cmd" &>/dev/null; then
            missing_cmds+=("$cmd")
        fi
    done
    
    # 检查结果
    if [ ${#missing_cmds[@]} -ne 0 ]; then
        error_message "缺少必要的命令: ${missing_cmds[*]}"
        log_message "ERROR" "缺少必要的命令: ${missing_cmds[*]}"
        return 1
    fi
    
    success_message "所有必要命令已就绪"
    log_message "INFO" "环境检查通过"
    return 0
}

# 获取用户输入的目录路径
get_user_path() {
    local default_path="$(pwd)/spotlight_wallpapers"
    
    echo -e "请输入您希望设置的壁纸下载目录路径:"
    echo -e "提示: 您可以使用绝对路径或相对路径"
    echo -e "示例: /path/to/wallpapers 或 ./wallpapers 或 ~/Pictures/wallpapers"
    echo -e "注意: 请确保您对该目录或其父目录有写入权限"
    echo -e "\n[按Enter使用默认路径: $default_path]"
    
    read -p "${YELLOW}下载目录路径: ${NC}" USER_INPUT_PATH
    
    # 如果用户未输入，使用默认路径
    if [ -z "$USER_INPUT_PATH" ]; then
        USER_INPUT_PATH="$default_path"
        echo -e "${YELLOW}使用默认路径: $default_path${NC}"
        log_message "INFO" "使用默认下载路径: $default_path"
    else
        log_message "INFO" "用户输入的下载路径: $USER_INPUT_PATH"
    fi
    
    echo "$USER_INPUT_PATH"
}

# 验证路径格式 - 修复了引号转义问题
validate_path_format() {
    local path="$1"
    
    # 移除路径两端的引号（如果存在）
    path=$(echo "$path" | sed -e 's/^\"//' -e 's/\"$//' -e "s/^'//" -e "s/'$//")
    
    # 检查路径是否为空
    if [ -z "$path" ]; then
        echo -e "${RED}错误: 路径不能为空${NC}"
        log_message "ERROR" "路径验证失败: 路径为空"
        return 1
    fi
    
    # 检查路径是否包含无效字符 - 使用简单安全的方法
    local invalid_chars="< > | ? * \" ' & ! $ ( ) \\"
    if echo "$path" | grep -q "[<>|?*\"'&!$()\\]"; then
        echo -e "${RED}错误: 路径包含无效字符${NC}"
        log_message "ERROR" "路径验证失败: 包含无效字符"
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
        log_message "ERROR" "路径验证失败: 路径过长"
        return 1
    fi
    
    echo "$path"
    return 0
}

# 创建目录并检查权限
create_directory() {
    local path="$1"
    local parent_dir="$(dirname "$path")"
    
    echo -e "\n${BLUE}正在处理下载目录: $path${NC}"
    
    # 检查路径是否为根目录的特殊情况
    if [ "$path" = "/" ]; then
        echo -e "${RED}错误: 不能使用根目录作为下载目录${NC}"
        log_message "ERROR" "尝试使用根目录作为下载目录"
        return 1
    fi
    
    # 检查父目录是否为有效的目录路径
    if [ "$parent_dir" != "/" ] && [ ! -d "$parent_dir" ]; then
        echo -e "${YELLOW}父目录 '$parent_dir' 不存在，尝试创建...${NC}"
        log_message "INFO" "尝试创建父目录: $parent_dir"
        
        # 尝试创建父目录（递归）
        if mkdir -p "$parent_dir"; then
            echo -e "${GREEN}父目录 '$parent_dir' 创建成功${NC}"
            log_message "INFO" "父目录创建成功: $parent_dir"
        else
            echo -e "${RED}错误: 无法创建父目录 '$parent_dir'，可能权限不足${NC}"
            log_message "ERROR" "无法创建父目录: $parent_dir"
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
        log_message "ERROR" "没有权限在 $parent_dir 中创建目录"
        return 1
    fi
    
    # 如果目录不存在，则创建它
    if [ ! -d "$path" ]; then
        echo -e "正在创建下载目录: $path"
        log_message "INFO" "正在创建下载目录: $path"
        
        # 创建目录并设置适当的权限
        if mkdir -p "$path" && chmod 755 "$path"; then
            echo -e "${GREEN}目录创建成功: $path${NC}"
            log_message "INFO" "下载目录创建成功: $path"
            
            # 验证创建是否成功
            if [ ! -d "$path" ]; then
                echo -e "${RED}错误: 目录创建后验证失败，路径仍然不存在${NC}"
                log_message "ERROR" "目录创建后验证失败: $path"
                return 1
            fi
            
            return 0
        else
            echo -e "${RED}错误: 无法创建目录 '$path'${NC}"
            echo -e "  请检查您是否有足够的权限和磁盘空间"
            log_message "ERROR" "无法创建目录: $path"
            return 1
        fi
    else
        # 检查现有目录的写入权限
        if [ ! -w "$path" ]; then
            echo -e "${RED}错误: 没有写入权限到目录 '$path'${NC}"
            echo -e "  请检查目录权限设置"
            log_message "ERROR" "没有写入权限到目录: $path"
            return 1
        fi
        
        # 检查目录的读取权限
        if [ ! -r "$path" ]; then
            echo -e "${RED}错误: 没有读取权限到目录 '$path'${NC}"
            log_message "ERROR" "没有读取权限到目录: $path"
            return 1
        fi
        
        # 检查目录的执行权限（需要进入目录）
        if [ ! -x "$path" ]; then
            echo -e "${RED}错误: 没有执行权限到目录 '$path'${NC}"
            log_message "ERROR" "没有执行权限到目录: $path"
            return 1
        fi
        
        echo -e "${GREEN}使用现有目录: $path${NC}"
        log_message "INFO" "使用现有目录: $path"
        
        # 验证目录是否真的可以写入文件
        test_file="$path/.spotlight_test_write"
        if touch "$test_file"; then
            rm -f "$test_file"
            echo -e "${GREEN}✓ 目录写入测试通过${NC}"
            log_message "INFO" "目录写入测试通过: $path"
        else
            echo -e "${RED}错误: 虽然有写入权限，但实际写入测试失败${NC}"
            log_message "ERROR" "目录写入测试失败: $path"
            return 1
        fi
        
        return 0
    fi
}

# 生成定制化的下载脚本
generate_custom_script() {
    local target_path="$1"
    local output_script="$2"
    
    echo -e "\n${BLUE}===== 生成定制化下载脚本 =====${NC}"
    log_message "INFO" "开始生成定制化脚本，目标路径: $target_path, 输出脚本: $output_script"
    
    # 检查是否提供了自定义源脚本
    if [ ! -z "$CUSTOM_SOURCE_SCRIPT" ]; then
        if [ -f "$CUSTOM_SOURCE_SCRIPT" ]; then
            echo -e "${YELLOW}注意: 使用自定义源脚本路径: $CUSTOM_SOURCE_SCRIPT${NC}"
            log_message "INFO" "检测到自定义源脚本: $CUSTOM_SOURCE_SCRIPT"
            # 这里只是提示，实际上我们仍然使用内置实现以保证稳定性
        else
            echo -e "${YELLOW}警告: 指定的自定义源脚本不存在: $CUSTOM_SOURCE_SCRIPT${NC}"
            echo -e "${YELLOW}将使用内置脚本内容${NC}"
            log_message "WARNING" "自定义源脚本不存在: $CUSTOM_SOURCE_SCRIPT，使用内置实现"
        fi
    fi
    
    # 确保输出目录存在
    local output_dir="$(dirname "$output_script")"
    if [ ! -d "$output_dir" ]; then
        echo -e "${YELLOW}输出目录 '$output_dir' 不存在，尝试创建...${NC}"
        log_message "INFO" "创建输出目录: $output_dir"
        if ! mkdir -p "$output_dir"; then
            echo -e "${RED}错误: 无法创建输出目录 '$output_dir'${NC}"
            log_message "ERROR" "无法创建输出目录: $output_dir"
            return 1
        fi
    fi
    
    # 检查输出文件是否已存在
    if [ -f "$output_script" ]; then
        # 备份现有文件
        local backup_script="${output_script}.bak.$(date +%Y%m%d_%H%M%S)"
        echo -e "${YELLOW}输出文件 '$output_script' 已存在，创建备份: $backup_script${NC}"
        log_message "INFO" "备份现有脚本到: $backup_script"
        if ! cp "$output_script" "$backup_script"; then
            echo -e "${YELLOW}警告: 无法创建备份文件${NC}"
            log_message "WARNING" "无法创建备份文件"
        fi
    fi
    
    # 生成定制化脚本
    echo -e "正在生成定制化脚本: $output_script"
    echo -e "设置下载路径: $target_path"
    
    # 使用临时文件进行修改
    local temp_file="$output_script.tmp"
    
    # 直接生成完整的脚本内容
    cat > "$temp_file" << EOF
#!/bin/bash

# ==================================================
# Windows Spotlight 壁纸下载器（自定义路径版）
# 此脚本由 create_download_script.sh 自动生成
# 生成时间: $(date +"%Y-%m-%d %H:%M:%S")
# 下载路径: $target_path
# ==================================================

# 壁纸保存路径
SAVE_FOLDER="$target_path"

# 日志文件路径
LOG_FILE="$SAVE_FOLDER/spotlight_wallpaper.log"

# API URL
API_URL="https://arc.msn.com/v3/Delivery/Placement?pid=209567&fmt=json&cdm=1&lc=en-US&ctry=US"

# 临时文件目录
TEMP_DIR="/tmp/spotlight_wallpaper"

# 最大重试次数
MAX_RETRIES=3

# 超时时间（秒）
TIMEOUT=30

# 下载工具优先级（curl 或 wget）
DOWNLOAD_TOOL=""

# 缓存文件路径
CACHE_FILE="$SAVE_FOLDER/wallpaper_cache.json"

# 定义颜色
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
PURPLE="\033[0;35m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color

# 记录日志函数
log_message() {
    local level="$1"
    local message="$2"
    local timestamp="$(date "+%Y-%m-%d %H:%M:%S")"
    local log_entry="[$timestamp] [$level] $message"
    
    # 写入日志文件
    echo "$log_entry" >> "$LOG_FILE"
    
    # 根据日志级别输出到控制台
    case "$level" in
        "ERROR") echo -e "${RED}$log_entry${NC}" ;;
        "WARNING") echo -e "${YELLOW}$log_entry${NC}" ;;
        "INFO") echo -e "${BLUE}$log_entry${NC}" ;;
        "SUCCESS") echo -e "${GREEN}$log_entry${NC}" ;;
        *) echo "$log_entry" ;;
    esac
}

# 创建目录函数
create_directory() {
    local dir_path="$1"
    
    if [ ! -d "$dir_path" ]; then
        log_message "INFO" "创建目录: $dir_path"
        mkdir -p "$dir_path" || {
            log_message "ERROR" "无法创建目录: $dir_path"
            return 1
        }
    fi
    
    return 0
}

# 检查下载工具函数
check_download_tool() {
    # 检查curl
    if command -v curl > /dev/null 2>&1; then
        DOWNLOAD_TOOL="curl"
        log_message "INFO" "使用curl作为下载工具"
        return 0
    fi
    
    # 检查wget
    if command -v wget > /dev/null 2>&1; then
        DOWNLOAD_TOOL="wget"
        log_message "INFO" "使用wget作为下载工具"
        return 0
    fi
    
    log_message "ERROR" "未找到curl或wget，无法下载文件"
    return 1
}

# 计算文件哈希值函数
calculate_hash() {
    local file_path="$1"
    
    # 检查md5sum
    if command -v md5sum > /dev/null 2>&1; then
        md5sum "$file_path" | awk '{print $1}'
        return 0
    fi
    
    # 检查md5 (macOS)
    if command -v md5 > /dev/null 2>&1; then
        md5 -q "$file_path"
        return 0
    fi
    
    log_message "WARNING" "未找到md5sum或md5，无法计算文件哈希值"
    return 1
}

# 保存缓存函数
save_cache() {
    local cache_data="$1"
    echo "$cache_data" > "$CACHE_FILE" || {
        log_message "ERROR" "无法保存缓存文件: $CACHE_FILE"
        return 1
    }
    return 0
}

# 添加到缓存函数
add_to_cache() {
    local file_name="$1"
    local file_hash="$2"
    local current_time="$(date +%s)"
    
    # 如果缓存文件不存在，创建空缓存
    if [ ! -f "$CACHE_FILE" ]; then
        echo "{}" > "$CACHE_FILE"
    fi
    
    # 读取现有缓存
    local cache_data=$(cat "$CACHE_FILE")
    
    # 检查jq是否可用
    if command -v jq > /dev/null 2>&1; then
        # 使用jq更新缓存
        local updated_cache=$(echo "$cache_data" | jq --arg name "$file_name" --arg hash "$file_hash" --arg time "$current_time" '.[$name] = {"hash": $hash, "timestamp": $time}')
        save_cache "$updated_cache"
    else
        # 简单的缓存更新（不使用jq）
        log_message "WARNING" "jq工具不可用，使用简单缓存模式"
        echo "$file_name:$file_hash:$current_time" >> "$CACHE_FILE"
    fi
    
    return 0
}

# 检查是否重复函数
is_duplicate() {
    local file_path="$1"
    local file_hash=$(calculate_hash "$file_path")
    
    # 如果无法计算哈希值，返回false（不重复）
    if [ -z "$file_hash" ]; then
        return 1
    fi
    
    # 如果缓存文件不存在，返回false（不重复）
    if [ ! -f "$CACHE_FILE" ]; then
        return 1
    fi
    
    # 检查jq是否可用
    if command -v jq > /dev/null 2>&1; then
        # 使用jq检查缓存
        local cache_data=$(cat "$CACHE_FILE")
        local hash_exists=$(echo "$cache_data" | jq -r ".[] | select(.hash == \"$file_hash\") | .hash")
        
        if [ ! -z "$hash_exists" ]; then
            return 0  # 重复
        fi
    else
        # 简单的缓存检查（不使用jq）
        if grep -q ":$file_hash:" "$CACHE_FILE"; then
            return 0  # 重复
        fi
    fi
    
    return 1  # 不重复
}

# 下载文件函数
download_file() {
    local url="$1"
    local output_path="$2"
    local retry_count=0
    local success=false
    
    log_message "INFO" "开始下载: $url"
    
    # 确保输出目录存在
    local output_dir=$(dirname "$output_path")
    create_directory "$output_dir"
    
    # 检查下载工具
    if [ -z "$DOWNLOAD_TOOL" ]; then
        if ! check_download_tool; then
            return 1
        fi
    fi
    
    while [ $retry_count -le $MAX_RETRIES ] && [ "$success" = false ]; do
        if [ $retry_count -gt 0 ]; then
            local backoff=$((2 ** retry_count))
            log_message "INFO" "第 $retry_count 次重试，等待 $backoff 秒..."
            sleep $backoff
        fi
        
        if [ "$DOWNLOAD_TOOL" = "curl" ]; then
            # 使用curl下载
            curl -s -L -o "$output_path" -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" --connect-timeout $TIMEOUT "$url"
            CURL_RESULT=$?
            
            if [ $CURL_RESULT -eq 0 ]; then
                success=true
            else
                log_message "WARNING" "curl下载失败，错误代码: $CURL_RESULT"
                retry_count=$((retry_count + 1))
            fi
        elif [ "$DOWNLOAD_TOOL" = "wget" ]; then
            # 使用wget下载
            wget -q -O "$output_path" --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" --timeout=$TIMEOUT "$url"
            WGET_RESULT=$?
            
            if [ $WGET_RESULT -eq 0 ]; then
                success=true
            else
                log_message "WARNING" "wget下载失败，错误代码: $WGET_RESULT"
                retry_count=$((retry_count + 1))
            fi
        fi
    done
    
    if [ "$success" = false ]; then
        log_message "ERROR" "下载失败，已达到最大重试次数: $MAX_RETRIES"
        rm -f "$output_path" 2>/dev/null
        return 1
    fi
    
    # 检查文件大小
    local file_size=$(stat -c '%s' "$output_path" 2>/dev/null || stat -f '%z' "$output_path" 2>/dev/null || echo 0)
    if [ $file_size -lt 1024 ]; then
        log_message "ERROR" "下载的文件太小，可能是错误的响应: ${file_size} 字节"
        rm -f "$output_path" 2>/dev/null
        return 1
    fi
    
    # 检查文件类型（简单检查文件头）
    local file_header=$(head -c 8 "$output_path" 2>/dev/null)
    
    # JPEG 文件头: FF D8 FF
    # PNG 文件头: 89 50 4E 47 0D 0A 1A 0A
    # WebP 文件头: 52 49 46 46 ?? ?? ?? ?? 57 45 42 50
    
    if [[ ! "$file_header" =~ ^\xff\xd8\xff && \
          ! "$file_header" =~ ^\x89PNG\r\n\x1a\n && \
          ! "$file_header" =~ ^RIFF....WEBP ]]; then
        log_message "ERROR" "下载的文件似乎不是有效的图片文件"
        rm -f "$output_path" 2>/dev/null
        return 1
    fi
    
    log_message "INFO" "下载成功: $output_path (${file_size} 字节)"
    return 0
}

# 主下载函数
main_download() {
    # 创建必要的目录
    create_directory "$SAVE_FOLDER"
    create_directory "$TEMP_DIR"
    
    # 检查下载工具
    if ! check_download_tool; then
        return 1
    fi
    
    log_message "INFO" "开始获取Spotlight壁纸..."
    
    # 获取API响应
    local api_response
    local temp_response="$TEMP_DIR/api_response.json"
    
    if [ "$DOWNLOAD_TOOL" = "curl" ]; then
        curl -s -L -o "$temp_response" -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" "$API_URL"
        if [ $? -ne 0 ]; then
            log_message "ERROR" "无法获取API响应（curl）"
            return 1
        fi
    elif [ "$DOWNLOAD_TOOL" = "wget" ]; then
        wget -q -O "$temp_response" --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" "$API_URL"
        if [ $? -ne 0 ]; then
            log_message "ERROR" "无法获取API响应（wget）"
            return 1
        fi
    fi
    
    # 检查响应文件是否为空
    if [ ! -s "$temp_response" ]; then
        log_message "ERROR" "API响应为空"
        return 1
    fi
    
    # 检查是否有jq工具
    if ! command -v jq > /dev/null 2>&1; then
        log_message "ERROR" "未找到jq工具，无法解析JSON响应"
        return 1
    fi
    
    # 检查JSON格式是否有效
    if ! jq empty "$temp_response" 2>/dev/null; then
        log_message "ERROR" "API响应不是有效的JSON格式"
        return 1
    fi
    
    # 提取壁纸URLs
    local image_urls=($(jq -r '.batchrsp.items[].item.media[].url' "$temp_response" 2>/dev/null))
    
    if [ ${#image_urls[@]} -eq 0 ]; then
        log_message "WARNING" "未能提取到任何壁纸URL"
        return 0  # 不是错误，只是没有找到新壁纸
    fi
    
    log_message "INFO" "找到 ${#image_urls[@]} 个壁纸URL"
    
    local success_count=0
    local error_count=0
    local duplicate_count=0
    
    # 下载每个壁纸
    for url in "${image_urls[@]}"; do
        # 提取文件名
        local file_name=$(basename "$url" | cut -d'?' -f1)
        
        # 如果文件名没有扩展名，添加.jpg
        if [[ "$file_name" != *.* ]]; then
            file_name="${file_name}.jpg"
        fi
        
        local output_path="$SAVE_FOLDER/$file_name"
        local temp_file="$TEMP_DIR/$file_name"
        
        # 下载文件
        if download_file "$url" "$temp_file"; then
            # 检查是否重复
            if is_duplicate "$temp_file"; then
                log_message "INFO" "壁纸已存在（重复）: $file_name"
                duplicate_count=$((duplicate_count + 1))
                rm -f "$temp_file" 2>/dev/null
            else
                # 移动到最终位置
                mv -f "$temp_file" "$output_path"
                
                # 添加到缓存
                local file_hash=$(calculate_hash "$output_path")
                add_to_cache "$file_name" "$file_hash"
                
                log_message "SUCCESS" "壁纸下载成功: $file_name"
                success_count=$((success_count + 1))
            fi
        else
            error_count=$((error_count + 1))
        fi
    done
    
    # 清理临时文件
    rm -rf "$TEMP_DIR" 2>/dev/null
    
    # 输出结果摘要
    log_message "INFO" "下载完成: 成功=$success_count, 失败=$error_count, 重复=$duplicate_count"
    
    if [ $success_count -gt 0 ]; then
        return 0
    elif [ $duplicate_count -gt 0 ]; then
        return 0  # 虽然没有新下载，但整体成功
    else
        return 1  # 全部失败
    fi
}

# 主函数
main() {
    echo -e "\n${CYAN}=========================================${NC}"
    echo -e "${CYAN}Windows Spotlight 壁纸下载器 v1.0.0${NC}"
    echo -e "${CYAN}=========================================${NC}\n"
    
    log_message "INFO" "开始运行Windows Spotlight壁纸下载器"
    
    # 显示配置信息
    echo -e "${BLUE}配置信息:${NC}"
    echo -e "  下载路径: $SAVE_FOLDER"
    echo -e "  缓存文件: $CACHE_FILE"
    echo -e "  API URL: $API_URL\n"
    
    # 加载缓存（如果存在）
    if [ -f "$CACHE_FILE" ]; then
        local cache_size=$(wc -l < "$CACHE_FILE" 2>/dev/null || echo 0)
        log_message "INFO" "加载缓存文件，包含 $cache_size 个条目"
        echo -e "${GREEN}✓ 缓存文件已加载${NC}"
    else
        log_message "INFO" "缓存文件不存在，将创建新的"
        echo -e "${YELLOW}! 缓存文件不存在，将创建新的${NC}"
    fi
    
    # 执行主下载流程
    main_download
    DOWNLOAD_RESULT=$?
    
    # 根据结果显示不同信息
    if [ $DOWNLOAD_RESULT -eq 0 ]; then
        echo -e "\n${GREEN}=========================================${NC}"
        echo -e "${GREEN}✅ 壁纸下载完成!${NC}"
        echo -e "${GREEN}=========================================${NC}"
        echo -e "\n${BLUE}下载的壁纸保存在:${NC} $SAVE_FOLDER"
    else
        echo -e "\n${RED}=========================================${NC}"
        echo -e "${RED}❌ 壁纸下载失败!${NC}"
        echo -e "${RED}=========================================${NC}"
        echo -e "\n${YELLOW}请检查网络连接或查看日志文件获取详细信息:${NC} $LOG_FILE"
    fi
    
    # 检查缓存保存
    if [ -f "$CACHE_FILE" ]; then
        log_message "INFO" "缓存文件已保存: $CACHE_FILE"
    else
        log_message "WARNING" "缓存文件未保存成功"
    fi
    
    log_message "INFO" "脚本执行完成"
    return $DOWNLOAD_RESULT
}

# 处理命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--source-script)
                CUSTOM_SOURCE_SCRIPT="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}未知参数: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
}

# 显示帮助信息
show_help() {
    echo -e "\n${CYAN}=========================================${NC}"
    echo -e "${CYAN}Windows Spotlight 壁纸下载器 - 脚本生成工具${NC}"
    echo -e "${CYAN}=========================================${NC}\n"
    echo -e "${BLUE}用法:${NC} $0 [选项]"
    echo -e "\n${BLUE}选项:${NC}"
    echo -e "  -s, --source-script <路径>  指定自定义的源脚本路径（可选）"
    echo -e "  -h, --help                  显示此帮助信息"
    echo -e "\n${BLUE}示例:${NC}"
    echo -e "  $0                         使用内置脚本内容生成下载脚本"
    echo -e "  $0 -s /path/to/script.sh   使用指定的源脚本生成下载脚本"
    echo -e "\n${YELLOW}注意:${NC} 即使指定了源脚本，大部分功能仍将使用内置实现，"
    echo -e "      这是为了保证脚本的兼容性和稳定性。"
}

# 初始化自定义源脚本变量
CUSTOM_SOURCE_SCRIPT=""

# 解析命令行参数
parse_arguments "$@"

# 执行主函数
main "$@"
EOF
    
    # 检查生成的文件内容
    if [ ! -f "$temp_file" ] || [ ! -s "$temp_file" ]; then
        echo -e "${RED}错误: 生成临时文件失败或文件为空${NC}"
        log_message "ERROR" "临时文件生成失败或为空: $temp_file"
        rm -f "$temp_file" 2>/dev/null
        return 1
    fi
    
    # 移动临时文件到最终位置
    if ! mv -f "$temp_file" "$output_script"; then
        echo -e "${RED}错误: 无法保存最终脚本文件${NC}"
        log_message "ERROR" "无法移动临时文件到目标位置"
        rm -f "$temp_file" 2>/dev/null
        return 1
    fi
    
    # 设置执行权限
    echo -e "正在设置脚本执行权限..."
    if ! chmod +x "$output_script"; then
        echo -e "${YELLOW}警告: 无法设置脚本执行权限，请手动运行: chmod +x $output_script${NC}"
        log_message "WARNING" "无法设置脚本执行权限: $output_script"
    else
        echo -e "${GREEN}✓ 脚本执行权限设置成功${NC}"
        log_message "INFO" "脚本执行权限设置成功: $output_script"
    fi
    
    # 验证生成的脚本
    if grep -q "SAVE_FOLDER=\"$target_path\"" "$output_script"; then
        echo -e "${GREEN}✓ 脚本生成成功${NC}"
        log_message "INFO" "定制化脚本生成成功: $output_script"
        return 0
    else
        echo -e "${RED}错误: 脚本生成失败，路径设置失败${NC}"
        log_message "ERROR" "无法在生成的脚本中找到更新的SAVE_FOLDER路径"
        return 1
    fi
}

# 主函数
main() {
    # 显示欢迎信息
    show_welcome
    log_message "INFO" "开始执行脚本生成工具 v$SCRIPT_VERSION"
    
    # 运行环境检查
    if ! test_environment; then
        log_message "ERROR" "环境检查失败，退出脚本"
        echo -e "\n${RED}=========================================${NC}"
        error_message "环境检查失败，脚本无法正常运行"
        echo -e "${RED}=========================================${NC}"
        exit $EXIT_CONFIG_ERROR
    fi
    
    # 检查脚本权限
    if [ ! -x "$0" ]; then
        warning_message "脚本没有执行权限，正在尝试添加..."
        if ! chmod +x "$0"; then
            warning_message "无法添加执行权限，请手动运行: chmod +x $0"
        fi
    fi
    
    success_message "脚本内容已内置，不需要外部依赖"
    log_message "INFO" "脚本内容已内置，不需要外部依赖"
    
    # 显示用户信息和环境
    local current_user=$(whoami 2>/dev/null || echo "unknown")
    info_message "当前用户: $current_user"
    
    # 显示操作系统类型
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        info_message "检测到操作系统: Linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        info_message "检测到操作系统: macOS"
    elif [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "win32"* ]]; then
        info_message "检测到操作系统: Windows"
    else
        info_message "检测到操作系统: $OSTYPE"
    fi
    
    # 1. 获取用户输入的目录路径
    USER_PATH=$(get_user_path)
    if [ -z "$USER_PATH" ]; then
        error_message "无法获取有效的目录路径"
        log_message "ERROR" "获取目录路径失败"
        exit $EXIT_ERROR
    fi
    
    # 2. 验证路径
    CLEAN_PATH=$(validate_path_format "$USER_PATH")
    VALIDATION_RESULT=$?
    
    if [ $VALIDATION_RESULT -ne 0 ]; then
        log_message "ERROR" "路径验证失败"
        echo -e "\n${RED}=========================================${NC}"
        error_message "路径验证失败，请重新运行脚本并输入有效的路径"
        echo -e "${RED}=========================================${NC}"
        exit $EXIT_INVALID_PATH
    fi
    
    # 路径验证成功后的确认
    log_message "INFO" "路径验证成功: $CLEAN_PATH"
    success_message "路径验证成功"
    
    # 确认路径
    if ! user_confirm "确认使用此路径作为壁纸下载目录? $CLEAN_PATH" "y"; then
        log_message "INFO" "用户取消了操作"
        echo -e "\n${YELLOW}=========================================${NC}"
        warning_message "操作已取消，脚本将退出"
        echo -e "${YELLOW}=========================================${NC}"
        exit $EXIT_USER_ABORT
    fi
    
    # 3. 创建目录
    echo -e "\n${BLUE}===== 创建下载目录 =====${NC}"
    create_directory "$CLEAN_PATH"
    DIR_RESULT=$?
    
    if [ $DIR_RESULT -ne 0 ]; then
        log_message "ERROR" "目录创建失败"
        echo -e "\n${RED}=========================================${NC}"
        error_message "无法创建或访问目录，请检查权限设置"
        echo -e "${RED}=========================================${NC}"
        exit $EXIT_PERMISSION_DENIED
    fi
    
    success_message "目录准备完成"
    
    # 4. 生成定制化脚本
    echo -e "\n${BLUE}===== 生成定制化脚本 =====${NC}"
    generate_custom_script "$CLEAN_PATH" "$GENERATED_SCRIPT"
    SCRIPT_RESULT=$?
    
    if [ $SCRIPT_RESULT -ne 0 ]; then
        log_message "ERROR" "定制化脚本生成失败"
        echo -e "\n${RED}=========================================${NC}"
        error_message "无法生成定制化脚本，请检查日志获取详细信息"
        echo -e "${RED}=========================================${NC}"
        exit $EXIT_SCRIPT_GENERATION_FAILED
    fi
    
    success_message "定制化脚本生成成功: $GENERATED_SCRIPT"
    
    # 5. 显示完成信息
    echo -e "\n${GREEN}=========================================${NC}"
    echo -e "${GREEN}🎉 所有设置已完成!${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo -e "\n${BLUE}📋 设置详情:${NC}"
    echo -e "  ${CYAN}• 下载目录:${NC} $CLEAN_PATH"
    echo -e "  ${CYAN}• 定制化脚本:${NC} $GENERATED_SCRIPT"
    echo -e "  ${CYAN}• 日志文件:${NC} $LOG_FILE"
    echo -e "\n${BLUE}🚀 使用方法:${NC}"
    echo -e "  ${GREEN}1.${NC} 运行定制化脚本: ${YELLOW}./$GENERATED_SCRIPT${NC}"
    echo -e "  ${GREEN}2.${NC} 脚本将自动下载Spotlight壁纸到指定目录"
    echo -e "  ${GREEN}3.${NC} 您可以将脚本添加到定时任务中定期更新壁纸"
    echo -e "\n${BLUE}🔧 定时任务示例 (crontab):${NC}"
    echo -e "  每天早上9点运行: ${YELLOW}0 9 * * * $(pwd)/$GENERATED_SCRIPT${NC}"
    echo -e "  每小时运行: ${YELLOW}0 * * * * $(pwd)/$GENERATED_SCRIPT${NC}"
    echo -e "\n${YELLOW}⚠️  注意:${NC}"
    echo -e "  • 请确保您有足够的磁盘空间存储壁纸"
    echo -e "  • 定期清理不需要的壁纸以节省空间"
    echo -e "  • 如有问题，请查看日志文件获取详细信息"
    echo -e "\n${GREEN}感谢使用Spotlight壁纸下载脚本生成工具!${NC}"
    
    log_message "INFO" "脚本执行完成，所有操作成功"
    return 0
}

# 执行主函数
main

# 退出脚本
exit $?