#!/bin/bash

# ==================================================
# Windows Spotlight 壁纸下载器（2025-11-22 永不翻车版）
# 已经彻底解决所有历史遗留问题
# ==================================================

# 使用Windows风格的保存路径
SAVE_FOLDER="/mnt/disk/spot"
IMAGE_NAME_BASE="spot_api_"
LOG_FILE="$(dirname "$0")/spotlight_wallpaper_log.txt"
API_URL="https://api.qzink.me/spotlight"
MAX_RETRIES=3
RETRY_DELAY=10
MIN_FILE_SIZE=1048576
HASH_CACHE_FILE="$(dirname "$0")/wallpaper_hash_cache.json"

log() {
    local msg="$1"
    local ts=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$ts] $msg" | tee -a "$LOG_FILE" >&2
}

ensure_dir() { mkdir -p "$1" 2>/dev/null || exit 1; }

get_sha256() {
    local file="$1"
    
    # 首先检查文件是否存在
    if [ ! -f "$file" ]; then
        log "警告: 文件不存在: $file"
        echo "null"
        return
    fi
    
    # 优先使用sha256sum (Linux/Armbian)
    if command -v sha256sum >/dev/null 2>&1; then
        local hash_value=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
        if [ -n "$hash_value" ] && [[ "$hash_value" =~ ^[a-fA-F0-9]{64}$ ]]; then
            echo "$hash_value"
            return
        fi
    # 其次使用openssl (跨平台)
    elif command -v openssl >/dev/null 2>&1; then
        local hash_value=$(openssl dgst -sha256 "$file" 2>/dev/null | awk '{print $NF}')
        if [ -n "$hash_value" ] && [[ "$hash_value" =~ ^[a-fA-F0-9]{64}$ ]]; then
            echo "$hash_value"
            return
        fi
    # 最后使用shasum (macOS)
    elif command -v shasum >/dev/null 2>&1; then
        local hash_value=$(shasum -a 256 "$file" 2>/dev/null | awk '{print $1}')
        if [ -n "$hash_value" ] && [[ "$hash_value" =~ ^[a-fA-F0-9]{64}$ ]]; then
            echo "$hash_value"
            return
        fi
    fi
    
    # 如果所有方法都失败或返回无效的哈希值
    log "警告: 无法计算有效的SHA256哈希值"
    echo "null"
}

# 保留旧函数以兼容现有缓存，但不再使用
get_md5() {
    local file="$1"
    
    # 首先检查文件是否存在
    if [ ! -f "$file" ]; then
        echo "null"
        return
    fi
    
    # 优先使用md5sum (Linux/Armbian)
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$file" 2>/dev/null | awk '{print $1}'
    # 其次使用openssl (跨平台)
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -md5 "$file" 2>/dev/null | awk '{print $NF}'
    # 最后使用shasum (macOS)
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 1 "$file" 2>/dev/null | awk '{print $1}'
    else
        echo "null"
    fi
}

new_cache() {
    printf '{"FileHashes":{},"LastUpdated":"%s","CacheVersion":"1.1","DefaultHashType":"SHA256"}\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}

# 缓存迁移函数 - 将旧格式缓存升级到支持SHA256的新格式
migrate_cache() {
    local old_cache="$1"
    if command -v jq >/dev/null 2>&1; then
        # 检查缓存是否已包含CacheVersion字段
        if ! echo "$old_cache" | jq -e '.CacheVersion' >/dev/null 2>&1; then
            log "正在迁移缓存至SHA256版本..."
            # 使用更兼容的jq语法，避免反斜杠问题
            local ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            echo "$old_cache" | jq --arg v "1.1" --arg ht "SHA256" --arg ts "$ts" \
                '. + {"CacheVersion": $v, "DefaultHashType": $ht, "LastUpdated": $ts} | \
                .FileHashes |= with_entries(if .value.HashType == null then .value += {"HashType": "MD5"} else . end)'
            return
        fi
    fi
    # 如果无需迁移或无jq，返回原缓存
    echo "$old_cache"
}

load_cache() {
    local cache
    local file_size
    
    log "开始加载缓存文件: $HASH_CACHE_FILE"
    
    # 安全地检查和加载缓存文件
    if [ -f "$HASH_CACHE_FILE" ]; then
        file_size=$(wc -c < "$HASH_CACHE_FILE" 2>/dev/null || echo 0)
        log "缓存文件存在，大小: ${file_size} 字节"
        
        if [ "$file_size" -eq 0 ]; then
            log "警告: 缓存文件存在但为空"
        else
            # 简化的读取方式，减少过度过滤
            cache=$(cat "$HASH_CACHE_FILE" 2>/dev/null)
            
            if [ -z "$cache" ]; then
                log "错误: 缓存文件内容为空或无法读取"
            else
                log "成功读取缓存文件，内容长度: ${#cache} 字符"
                
                # 基础格式检查
                if [[ "$cache" == *"{"* ]] && [[ "$cache" == *"}"* ]]; then
                    log "缓存文件包含JSON结构，尝试处理"
                    
                    # 清理可能的BOM和多余字符，但保留核心JSON结构
                    cache=$(echo "$cache" | tr -d '\r' | sed 's/^[^\{]*//' | sed 's/[^\}]*$//')
                    log "清理后的缓存长度: ${#cache} 字符"
                    
                    # 再次检查核心结构
                    if [ -n "$cache" ] && [ "${cache:0:1}" = "{" ] && [ "${cache: -1}" = "}" ]; then
                        log "缓存结构基本有效"
                        
                        # 使用jq进行验证和清理（如果可用）
                        if command -v jq >/dev/null 2>&1; then
                            log "使用jq验证和清理缓存格式"
                            local cleaned_cache=$(echo "$cache" | jq . 2>/dev/null)
                            
                            if [ $? -eq 0 ] && [ -n "$cleaned_cache" ]; then
                                log "✅ jq验证通过，缓存格式有效"
                                # 使用清理后的缓存
                                cache="$cleaned_cache"
                                # 调用缓存迁移函数
                                log "调用迁移函数以确保缓存格式最新"
                                migrate_cache "$cache"
                                return
                            else
                                log "⚠️  jq验证失败，但尝试使用原始缓存结构"
                                # 即使jq验证失败，仍然尝试使用原始结构
                                log "尝试使用原始缓存结构调用迁移函数"
                                migrate_cache "$cache"
                                return
                            fi
                        else
                            log "jq不可用，使用基本格式验证"
                            # 调用缓存迁移函数
                            log "调用迁移函数处理缓存"
                            migrate_cache "$cache"
                            return
                        fi
                    else
                        log "警告: 缓存文件内容过滤后结构无效"
                        log "尝试使用原始未过滤内容"
                        # 尝试使用原始内容
                        cache=$(cat "$HASH_CACHE_FILE" 2>/dev/null)
                        if [ -n "$cache" ]; then
                            log "尝试使用原始内容调用迁移函数"
                            migrate_cache "$cache"
                            return
                        fi
                    fi
                else
                    log "警告: 缓存文件不包含有效的JSON结构"
                fi
            fi
        fi
        # 如果所有尝试都失败，记录日志并创建新缓存
        log "缓存文件格式无效或无法恢复，已重建"
    else
        log "缓存文件不存在，创建新缓存"
    fi
    
    # 创建新的干净缓存
    log "创建全新的缓存结构"
    new_cache
}

save_cache() {
    local cache="$1"
    local save_success=false
    
    log "开始保存缓存到: $HASH_CACHE_FILE"
    
    # 1. 验证缓存内容格式
    if [ -z "$cache" ]; then
        log "错误: 缓存内容为空，无法保存"
    elif [ "${cache:0:1}" != "{" ] || [ "${cache: -1}" != "}" ]; then
        log "错误: 缓存内容不是有效的JSON格式（缺少{}）"
        # 尝试提取可能的JSON内容
        local extracted_cache=$(echo "$cache" | sed 's/^[^\{]*//' | sed 's/[^\}]*$//')
        if [ -n "$extracted_cache" ] && [ "${extracted_cache:0:1}" = "{" ] && [ "${extracted_cache: -1}" = "}" ]; then
            log "尝试使用提取的有效JSON部分: ${#extracted_cache} 字符"
            cache="$extracted_cache"
        fi
    fi
    
    # 2. 尝试使用jq进行最终验证（如果可用）
    if command -v jq >/dev/null 2>&1; then
        if echo "$cache" | jq empty 2>/dev/null; then
            log "✅ jq验证通过，缓存是有效的JSON格式"
        else
            log "❌ jq验证失败，缓存JSON格式无效"
            # 准备一个新的默认缓存
            cache=$(new_cache)
            log "已使用新的默认缓存替换无效内容"
        fi
    else
        log "jq不可用，使用基本格式检查"
    fi
    
    # 3. 保存缓存到临时文件，然后验证后再移动
    local temp_file="$HASH_CACHE_FILE.tmp"
    log "将缓存保存到临时文件: $temp_file"
    echo "$cache" > "$temp_file" 2>/dev/null
    
    # 4. 验证保存是否成功
    if [ $? -eq 0 ] && [ -s "$temp_file" ]; then
        # 检查临时文件大小
        local temp_size=$(wc -c < "$temp_file")
        log "临时文件保存成功，大小: ${temp_size} 字节"
        
        # 5. 将临时文件移动到目标位置（原子操作）
        mv -f "$temp_file" "$HASH_CACHE_FILE" 2>/dev/null
        if [ $? -eq 0 ]; then
            log "✅ 缓存文件保存成功"
            save_success=true
            
            # 6. 读取并验证保存的缓存
            local saved_cache=$(cat "$HASH_CACHE_FILE" 2>/dev/null)
            if [ -n "$saved_cache" ] && [ "${saved_cache:0:1}" = "{" ] && [ "${saved_cache: -1}" = "}" ]; then
                log "✅ 保存的缓存文件内容验证通过"
                local file_count=$(echo "$saved_cache" | jq '.FileHashes | length' 2>/dev/null || echo "未知")
                log "保存的缓存包含 $file_count 个文件记录"
            else
                log "⚠️  保存的缓存文件内容可能无效"
            fi
        else
            log "❌ 无法将临时文件移动到目标位置"
            rm -f "$temp_file" 2>/dev/null
        fi
    else
        log "❌ 临时文件保存失败或为空"
        rm -f "$temp_file" 2>/dev/null
    fi
    
    # 7. 如果保存失败，创建新缓存
    if ! $save_success; then
        log "❌ 缓存保存失败，创建新缓存"
        new_cache > "$HASH_CACHE_FILE" 2>/dev/null
        if [ $? -eq 0 ]; then
            log "✅ 已成功创建新的默认缓存"
        else
            log "❌ 无法创建新缓存，可能是权限问题"
        fi
    fi
}

add_to_cache() {
    # 确保参数顺序：cache在前，file_path在后
    local cache="$1"
    local file_path="$2"
    local file_name=$(basename "$file_path")
    local key=$(echo "$file_path" | tr '[:upper:]' '[:lower:]')
    local hash=$(get_sha256 "$file_path")
    
    # 确保获得有效的哈希值
    if [ "$hash" = "null" ] || [ -z "$hash" ]; then
        log "警告: 无法计算文件哈希值，跳过缓存更新"
        echo "$cache"
        return
    fi
    
    local ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    log "尝试将文件 $file_name 的SHA256值添加到缓存"
    
    # 检查jq是否可用
    if command -v jq >/dev/null 2>&1; then
        # 创建新的文件哈希记录
        local file_record="{\"Hash\": \"$hash\", \"HashType\": \"SHA256\", \"FileName\": \"$file_name\", \"Added\": \"$ts\"}"
        
        # 构建完整的更新命令
        log "准备使用jq更新缓存，key: $key"
        local updated_cache=
        # 确保FileHashes对象存在并正确设置
        updated_cache=$(echo "$cache" | \
            jq --arg key "$key" \
               --argjson record "$file_record" \
               --arg time "$ts" \
               '.LastUpdated = $time | .FileHashes = (.FileHashes // {}) | .FileHashes[$key] = $record' 2>/dev/null)
        
        # 检查jq命令是否成功执行
        if [ $? -eq 0 ] && [ -n "$updated_cache" ] && [ "${updated_cache:0:1}" = "{" ]; then
            # 验证FileHashes是否真的包含了新记录
            local has_record=$(echo "$updated_cache" | jq --arg key "$key" '.FileHashes | has($key)' 2>/dev/null)
            local record_count=$(echo "$updated_cache" | jq '.FileHashes | length' 2>/dev/null)
            log "jq命令执行成功，新缓存包含 $record_count 条记录，新记录存在: $has_record"
            log "文件SHA256值已成功添加到缓存"
            echo "$updated_cache"
        else
            log "错误: jq命令执行失败，无法更新缓存，返回码: $?"
            log "更新的缓存内容: $updated_cache"
            echo "$cache"
        fi
    else
        # 没有jq时的简单处理，直接返回原缓存
        log "警告: jq不可用，无法更新缓存"
        echo "$cache"
    fi
}

is_duplicate() {
    # 确保参数顺序：cache在前，file_path在后
    local cache="$1"
    local file_path="$2"
    local file_name=$(basename "$file_path")
    
    # 首先获取文件的SHA256哈希值
    log "正在计算文件 $file_path 的SHA256值进行重复检测"
    local hash=$(get_sha256 "$file_path")
    
    if [ "$hash" = "null" ] || [ -z "$hash" ]; then
        log "警告: 无法计算文件哈希值，假设不是重复"
        return 1
    fi
    
    log "检查SHA256值: $hash 是否在缓存中存在"
    
    # 检查jq是否可用
    if command -v jq >/dev/null 2>&1; then
        # 检查缓存是否有效
        if [ -z "$cache" ] || [ "$cache" = "null" ] || [ "${cache:0:1}" != "{" ]; then
            log "缓存数据无效，跳过重复检测"
            return 1
        fi
        
        log "使用jq精确检查缓存中的哈希值"
        # 使用any函数更高效地在所有缓存记录中搜索相同的哈希值
        local hash_exists=$(echo "$cache" | jq --arg hash "$hash" 'any(.FileHashes[]; .Hash == $hash)' 2>/dev/null || echo "false")
        
        if [[ "$hash_exists" == "true" ]]; then
            log "✅ jq检测: 文件是重复的，SHA256值 $hash 已存在于缓存中"
            return 0 # 是重复
        else
            log "文件不是重复的，SHA256值 $hash 不在缓存中"
            return 1 # 不是重复
        fi
    else
        # 无jq环境下使用更精确的grep搜索
        log "使用文本搜索检查缓存中的哈希值"
        if echo "$cache" | grep -Fq '"Hash":"'"$hash"'"'; then
            log "✅ grep检测: 文件是重复的，SHA256值 $hash 已存在于缓存中"
            return 0
        else
            log "文件不是重复的，SHA256值 $hash 不在缓存中"
            return 1
        fi
    fi
}

download_file() {
    local url="$1" path="$2"
    local i=0
    local expected_size=0
    local actual_size=0
    local http_status=0
    local download_success=false
    
    # 指数退避算法参数配置
    local base_delay=${RETRY_DELAY:-1}  # 基础延迟时间（秒）
    local max_delay=${MAX_RETRY_DELAY:-60}  # 最大延迟时间（秒）
    local jitter_factor=0.1  # 抖动因子，增加随机性以避免雪崩效应
    
    # 网络超时设置
    local connect_timeout=10  # 连接超时时间（秒）
    local read_timeout=30     # 读取超时时间（秒）
    local total_timeout=60    # 总超时时间（秒）
    
    # 先创建临时文件以避免部分下载的文件污染
    local temp_path="${path}.tmp"
    rm -f "$temp_path" 2>/dev/null
    
    while [ $i -lt $MAX_RETRIES ]; do
        i=$((i+1))
        log "下载中（第 $i/$MAX_RETRIES 次尝试）..."
        
        # 重置下载成功标志
        download_success=false
        
        # 使用curl获取HTTP状态码和Content-Length
        if command -v curl >/dev/null 2>&1; then
            log "使用curl下载文件..."
            
            # 设置curl重试参数
            local curl_retries=$((MAX_RETRIES-i+1))  # 根据剩余尝试次数调整curl内部重试
            
            # 获取响应头信息，增加重试和超时设置
            local headers=$(curl -I -sSL --max-time 30 --connect-timeout $connect_timeout --retry 1 "$url" 2>/dev/null)
            
            # 提取HTTP状态码
            http_status=$(echo "$headers" | grep -i "HTTP/" | awk '{print $2}' | head -1)
            
            # 提取Content-Length（如果有）
            expected_size=$(echo "$headers" | grep -i "Content-Length:" | awk '{print $2}' | tr -d '
')
            
            log "HTTP状态码: $http_status, 期望文件大小: ${expected_size:-未知}"
            
            # 错误分类处理
            if [[ -z "$http_status" ]]; then
                log "❌ 网络错误：无法连接到服务器或DNS解析失败"
            elif [[ "$http_status" == "404" || "$http_status" == "410" ]]; then
                log "❌ 资源错误：文件不存在（$http_status）"
                # 这类错误通常不需要重试，直接退出
                break
            elif [[ "$http_status" == "429" || "$http_status" == "403" ]]; then
                log "❌ 限流错误：请求过于频繁或权限不足（$http_status）"
                # 对于限流错误，增加延迟
                base_delay=$((base_delay * 2))
            elif [[ "$http_status" == "500" || "$http_status" == "502" || "$http_status" == "503" || "$http_status" == "504" ]]; then
                log "❌ 服务器错误：服务器暂时不可用（$http_status）"
            elif [[ "$http_status" == "200" || "$http_status" == "206" || ("$http_status" =~ ^3 && "$http_status" != "304") ]]; then
                # 只有状态码为200或3xx重定向成功时才继续
                # 执行实际下载，使用--progress-bar获取进度，增加更完善的参数
                curl -sSL --progress-bar \
                    --max-time $total_timeout \
                    --connect-timeout $connect_timeout \
                    --retry $curl_retries \
                    --retry-delay $base_delay \
                    --retry-max-time $((total_timeout * 2)) \
                    --speed-time 10 \
                    --speed-limit 100 \
                    "$url" -o "$temp_path" 2>/dev/null
                local curl_exit=$?
                
                # 强制刷新文件系统缓冲区
                sync "$temp_path" 2>/dev/null || true
                
                # 检查下载是否成功且文件存在
                if [ $curl_exit -eq 0 ] && [ -f "$temp_path" ]; then
                    actual_size=$(wc -c < "$temp_path")
                    log "curl下载完成，实际文件大小: $actual_size 字节"
                    
                    # 如果有期望大小，则验证文件大小是否匹配
                    if [ -n "$expected_size" ] && [ "$expected_size" -gt 0 ] && [ "$actual_size" -eq "$expected_size" ]; then
                        log "✅ 文件大小验证通过：期望 $expected_size 字节，实际 $actual_size 字节"
                        download_success=true
                        break
                    elif [ -n "$expected_size" ] && [ "$expected_size" -gt 0 ]; then
                        log "❌ 文件大小不匹配：期望 $expected_size 字节，实际 $actual_size 字节"
                    else
                        log "文件大小无法验证（服务器未提供Content-Length）"
                        # 继续使用，因为至少文件已下载
                        download_success=true
                        break
                    fi
                else
                    case $curl_exit in
                        6) log "❌ curl错误：无法解析主机名（DNS失败）" ;;
                        7) log "❌ curl错误：无法连接到主机" ;;
                        28) log "❌ curl错误：操作超时" ;;
                        36) log "❌ curl错误：上传/下载失败" ;;
                        56) log "❌ curl错误：接收失败（可能是网络中断）" ;;
                        *) log "❌ curl下载失败，退出码: $curl_exit" ;;
                    esac
                fi
            else
                log "❌ 服务器返回非成功状态码: $http_status"
            fi
        fi
        
        # 如果curl失败或不可用，尝试使用wget
        if command -v wget >/dev/null 2>&1 && [ ! -s "$temp_path" ]; then
            log "使用wget尝试下载..."
            
            # 设置wget重试参数
            local wget_retries=$((MAX_RETRIES-i+1))
            
            # 执行实际下载，添加更完善的参数
            wget -q --timeout=$total_timeout \
                --connect-timeout=$connect_timeout \
                --read-timeout=$read_timeout \
                --tries=$wget_retries \
                --wait=$base_delay \
                --show-progress \
                -O "$temp_path" "$url" 2>/dev/null
            local wget_exit=$?
            
            # 强制刷新文件系统缓冲区
            sync "$temp_path" 2>/dev/null || true
            
            if [ $wget_exit -eq 0 ] && [ -f "$temp_path" ]; then
                actual_size=$(wc -c < "$temp_path")
                log "wget下载完成，实际文件大小: $actual_size 字节"
                download_success=true
                break
            else
                case $wget_exit in
                    1) log "❌ wget错误：通用错误" ;;
                    2) log "❌ wget错误：解析主机失败" ;;
                    4) log "❌ wget错误：网络错误" ;;
                    8) log "❌ wget错误：服务器错误响应" ;;
                    15) log "❌ wget错误：超时" ;;
                    *) log "❌ wget下载失败，退出码: $wget_exit" ;;
                esac
            fi
        fi
        
        # 计算指数退避延迟时间
        if [ $i -lt $MAX_RETRIES ]; then
            # 计算指数退避时间：base_delay * (2 ^ (i-1))
            local delay=$((base_delay * (2 ** (i-1))))
            
            # 应用抖动，增加随机性
            if [ $delay -gt 0 ]; then
                # 计算抖动范围（±10%）
                local jitter=$((delay * jitter_factor * 100))
                jitter=$((jitter / 100))
                
                # 随机选择正负抖动
                local random_jitter=$((RANDOM % (jitter * 2 + 1) - jitter))
                delay=$((delay + random_jitter))
            fi
            
            # 确保延迟不超过最大值
            [ $delay -gt $max_delay ] && delay=$max_delay
            [ $delay -lt 1 ] && delay=1
            
            log "下载失败，将在 $delay 秒后重试...（指数退避算法）"
            sleep $delay
        fi
    done
    
    # 验证下载的文件是否为有效图片（检查文件头）
    if [ -f "$temp_path" ] && [ -s "$temp_path" ]; then
        # 增强兼容性的文件头读取方法
        local file_header=""
        
        # 尝试多种方法读取文件头
        if command -v xxd >/dev/null 2>&1 && command -v head >/dev/null 2>&1; then
            # Linux/Unix/macOS 标准方法
            file_header=$(head -c 12 "$temp_path" 2>/dev/null | xxd -p -c 12 2>/dev/null || echo "")
        elif command -v od >/dev/null 2>&1; then
            # 备选方法：使用od命令
            file_header=$(od -An -tx1 -N12 "$temp_path" 2>/dev/null | tr -d ' \n' || echo "")
        else
            # 如果没有工具可用，记录警告但继续
            log "警告: 无法使用xxd或od读取文件头进行验证"
            file_header=""
        fi
        
        # 检查常见图片格式的文件头
        # JPEG: FF D8 FF
        # PNG: 89 50 4E 47 0D 0A 1A 0A
        # WebP: RIFF....WEBP (52494646开头，后面4字节任意，然后是57454250)
        if [[ "$file_header" == ffd8ff* || "$file_header" == 89504e47* || "$file_header" == 52494646*57454250* ]]; then
            log "✅ 文件头验证通过，看起来是有效的图片文件"
            
            # 验证最小文件大小要求
            actual_size=$(wc -c < "$temp_path")
            if [ "$actual_size" -gt "$MIN_FILE_SIZE" ]; then
                log "✅ 文件大小满足最小要求（>$MIN_FILE_SIZE 字节）"
                # 标准mv命令
                mv -f "$temp_path" "$path" 2>/dev/null
                if [ $? -eq 0 ]; then
                    log "✅ 文件已成功保存到: $path"
                    return 0
                else
                    log "❌ 无法将临时文件移动到目标位置（标准mv命令）"
                fi
            else
                log "❌ 文件大小不满足最小要求（<$MIN_FILE_SIZE 字节）"
            fi
        else
            log "❌ 文件头验证失败，可能不是有效的图片文件，文件头: ${file_header:-空}"
            # 保存文件头以供调试
            if [ -n "$file_header" ] && [ ${#file_header} -gt 0 ]; then
                log "   十六进制文件头: $file_header"
            fi
        fi
    fi
    
    # 清理临时文件
    if [ -f "$temp_path" ]; then
        rm -f "$temp_path" 2>/dev/null
        log "已清理临时文件"
    fi
    log "❌ 下载失败或文件无效"
    return 1
}

main_download() {
    local cache="$1"
    log "正在获取最新壁纸..."

    # 获取API数据，添加超时设置和详细的错误处理
    log "尝试连接API: $API_URL"
    local json=""
    
    # 首先尝试curl
    if command -v curl >/dev/null 2>&1; then
        log "使用curl请求API数据..."
        json=$(curl -fsSL --connect-timeout 10 --max-time 30 "$API_URL" 2>/tmp/curl_error.log || echo "")
        
        if [ -z "$json" ] && [ -f "/tmp/curl_error.log" ]; then
            local curl_error=$(cat /tmp/curl_error.log | tr '\n' ' ')
            log "curl请求失败: $curl_error"
            rm -f /tmp/curl_error.log
        fi
    fi
    
    # 如果curl失败，尝试wget
    if [ -z "$json" ] && command -v wget >/dev/null 2>&1; then
        log "curl失败，尝试使用wget..."
        json=$(wget -qO- --timeout=30 "$API_URL" 2>/tmp/wget_error.log || echo "")
        
        if [ -z "$json" ] && [ -f "/tmp/wget_error.log" ]; then
            local wget_error=$(cat /tmp/wget_error.log | tr '\n' ' ')
            log "wget请求失败: $wget_error"
            rm -f /tmp/wget_error.log
        fi
    fi
    
    # Linux环境下仅使用curl和wget方法
    
    # 验证API响应
    if [ -z "$json" ]; then
        log "无法连接API或API返回空数据"
        # 输出调试信息
        log "调试信息: 环境变量PATH=$PATH"
        log "调试信息: 检查网络连接状态..."
        if command -v ping >/dev/null 2>&1; then
            ping -c 1 api.qzink.me >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                log "调试信息: 能够ping通API主机"
            else
                log "调试信息: 无法ping通API主机"
            fi
        fi
        return 1
    fi
    
    log "成功获取API数据，长度: ${#json} 字符"
    # 记录JSON前50个字符以便调试（不记录完整内容以防过大）
    if [ ${#json} -gt 50 ]; then
        log "JSON响应预览: ${json:0:50}..."  
    else
        log "JSON响应: $json"
    fi

    # 提取图片URL
    local img_url
    if command -v jq >/dev/null 2>&1; then
        img_url=$(echo "$json" | jq -r '.landscape_url // .portrait_url // empty')
    else
        img_url=$(echo "$json" | grep -o '"landscape_url":"[^"]*' | cut -d'"' -f4)
        [ -z "$img_url" ] && img_url=$(echo "$json" | grep -o '"portrait_url":"[^"]*' | cut -d'"' -f4)
    fi
    [ -z "$img_url" ] && log "无有效图片链接" && return 1

    # 准备文件信息
    local ext="${img_url##*.}"
    [[ "$ext" =~ ^(jpg|jpeg|png|webp)$ ]] || ext="jpg"
    local filename="${IMAGE_NAME_BASE}$(date +%Y%m%d_%H%M%S).$ext"
    local fullpath="$SAVE_FOLDER/$filename"

    log "📁 准备下载: $filename"

    # 先清理可能存在的同名文件
    [ -f "$fullpath" ] && rm -f "$fullpath"

    # 下载文件
    if download_file "$img_url" "$fullpath"; then
        # 检查文件是否真的下载成功且有内容
        if [ ! -f "$fullpath" ] || [ ! -s "$fullpath" ]; then
            log "❌ 下载的文件为空或无效"
            return 1
        fi
        
        log "📊 文件下载成功，大小: $(du -h "$fullpath" 2>/dev/null | cut -f1 || echo "未知")"
        
        # 使用SHA256检查重复
        log "🔍 使用SHA256检查文件是否重复"
        if is_duplicate "$cache" "$fullpath"; then
            log "✅ 已跳过重复壁纸"
            rm -f "$fullpath"
            return 2
        fi
        
        # 获取文件信息
        local file_size=$(du -h "$fullpath" 2>/dev/null | cut -f1 || echo "未知")
        
        # 计算并记录SHA256值
        local file_hash=$(get_sha256 "$fullpath")
        log "📋 新壁纸保存成功 → $filename（$file_size）"
        log "🔒 SHA256哈希值: $file_hash"
        
        echo "$fullpath"
        return 0
    else
        log "❌ 下载失败或文件太小"
        return 1
    fi
}

# ===================== 主程序 =====================
echo "=================================================="
echo "   Windows Spotlight 壁纸下载器（永不翻车版）"
echo "=================================================="

# 确保保存目录存在
if ! ensure_dir "$SAVE_FOLDER"; then
    echo "× 无法创建保存目录：$SAVE_FOLDER"
    echo "请检查权限或修改脚本中的SAVE_FOLDER变量"
    exit 1
fi

log "脚本启动"

# 显示配置信息
log "配置信息:"
log "- 保存目录: $SAVE_FOLDER"
log "- 缓存文件: $HASH_CACHE_FILE"
log "- 使用SHA256进行文件去重"

# 安全加载缓存，确保获得有效的JSON
log "正在加载SHA256缓存..."
CACHE=$(load_cache)
if [ -z "$CACHE" ] || [ "${CACHE:0:1}" != "{" ]; then
    log "警告: 缓存加载失败，使用空缓存"
    CACHE=$(new_cache)
    log "已创建新的SHA256缓存结构"
else
    # 显示缓存统计信息
    CACHE_VERSION=$(echo "$CACHE" | jq -r '.CacheVersion // "未知"' 2>/dev/null)
    FILE_COUNT=$(echo "$CACHE" | jq '.FileHashes | length' 2>/dev/null)
    log "缓存版本: $CACHE_VERSION"
    log "已缓存文件数量: $FILE_COUNT"
fi

# 执行下载并捕获结果
log "开始下载最新壁纸..."
RESULT=$(main_download "$CACHE")
CODE=$?

# 处理下载结果
if [ $CODE -eq 0 ]; then
    # 从RESULT中提取实际的文件路径
    ACTUAL_FILE=$(echo "$RESULT" | grep -o "$SAVE_FOLDER/[^[:space:]]*" | head -1)
    
    # 如果找不到路径，使用RESULT作为后备
    if [ -z "$ACTUAL_FILE" ]; then
        ACTUAL_FILE="$RESULT"
    fi
    
    # 再次检查文件是否真的存在
    if [ -f "$ACTUAL_FILE" ]; then
        echo "√ 新壁纸已保存：$ACTUAL_FILE"
        
        # 确保add_to_cache返回有效JSON
        log "正在将文件SHA256值添加到缓存..."
        NEW_CACHE=$(add_to_cache "$CACHE" "$ACTUAL_FILE")
        
        if [ -n "$NEW_CACHE" ] && [ "${NEW_CACHE:0:1}" = "{" ]; then
            CACHE="$NEW_CACHE"
            log "✅ 文件SHA256值已成功添加到缓存"
            
            # 验证缓存是否真的更新了
            NEW_FILE_COUNT=$(echo "$CACHE" | jq '.FileHashes | length' 2>/dev/null)
            # 检查NEW_FILE_COUNT是否有效
            if [ -z "$NEW_FILE_COUNT" ] || ! [[ "$NEW_FILE_COUNT" =~ ^[0-9]+$ ]]; then
                NEW_FILE_COUNT=0
                log "警告: 无法获取缓存文件数量"
            fi
            
            log "原缓存文件数量: $FILE_COUNT, 新缓存文件数量: $NEW_FILE_COUNT"
            
            # 检查FileHashes是否真的包含了新记录
            cache_preview=$(echo "$CACHE" | jq '.FileHashes')
            log "缓存FileHashes内容: $cache_preview"
            
            if [ "$NEW_FILE_COUNT" -gt "$FILE_COUNT" ]; then
                log "✅ 缓存文件数量增加到: $NEW_FILE_COUNT"
            else
                log "⚠️  缓存文件数量未增加，可能更新未生效"
            fi
        else
            log "❌ 警告: 缓存更新失败，保留原缓存"
        fi
    else
        log "⚠️  状态码为0但文件不存在: $ACTUAL_FILE"
    fi
elif [ $CODE -eq 2 ]; then
    log "✅ 未下载重复壁纸，使用现有缓存"
elif [ $CODE -eq 1 ]; then
    log "❌ 下载失败或无有效图片"
else
    log "❓ 下载过程中出现未知错误，状态码: $CODE"
fi

# 安全保存缓存
log "正在保存SHA256缓存..."
save_cache "$CACHE"

# 最终验证缓存文件
if [ -f "$HASH_CACHE_FILE" ]; then
    CACHE_SIZE=$(du -h "$HASH_CACHE_FILE" 2>/dev/null | cut -f1 || echo "未知")
    log "缓存文件大小: $CACHE_SIZE"
    
    # 显示缓存文件内容预览
    echo "\n缓存文件内容预览:"
    cat "$HASH_CACHE_FILE" | jq
    echo ""
else
    log "警告: 缓存文件未找到或创建失败"
fi

log "脚本结束"

# 显示结果，避免在结果字符串中显示日志信息
case $CODE in
    0) 
        # 使用之前提取的实际文件路径
        if [ -n "$ACTUAL_FILE" ] && [ -f "$ACTUAL_FILE" ]; then
            echo "√ 新壁纸已保存：$ACTUAL_FILE" 
        else
            # 清理RESULT，只显示文件路径作为后备
            CLEAN_RESULT=$(echo "$RESULT" | grep -o "$SAVE_FOLDER/[^[:space:]]*" | head -1)
            [ -z "$CLEAN_RESULT" ] && CLEAN_RESULT="$RESULT"
            echo "√ 新壁纸已保存：$CLEAN_RESULT" 
        fi
        ;;
    2) echo "√ 今日壁纸已存在，无需重复下载" ;;
    *) echo "× 暂无新壁纸，晚点再试~" ;;
esac

log "脚本结束"
echo "=================================================="
exit 0