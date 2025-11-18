#!/bin/bash

# 系统巡检脚本
# 作者：[luobolun]
# 功能：自动检查系统状态并生成HTML报告

# 配置变量
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/monitor.conf"
LOG_FILE="$SCRIPT_DIR/../logs/system_check_$(date +%Y%m%d).log"
HTML_REPORT="$SCRIPT_DIR/../templates/daily_report_$(date +%Y%m%d).html"
EMAIL_SUBJECT="每日系统巡检报告 - $(date '+%Y年%m月%d日')"
ADMIN_EMAIL="admin@example.com"  # 修改为实际邮箱

# 颜色定义（用于终端输出）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: $1" >> "$LOG_FILE"
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" >> "$LOG_FILE"
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "命令 $1 未找到，请安装相应软件包"
        return 1
    fi
    return 0
}

# 初始化检查
initialize_checks() {
    log_message "开始系统巡检..."
    
    # 检查必要命令
    for cmd in df free uptime ps; do
        check_command "$cmd" || exit 1
    done
    
    # 创建必要的目录和文件
    mkdir -p "$(dirname "$CONFIG_FILE")" "$(dirname "$LOG_FILE")" "$(dirname "$HTML_REPORT")"
    
    # 如果配置文件不存在，创建默认配置
    if [ ! -f "$CONFIG_FILE" ]; then
        create_default_config
    fi
}

# 创建默认配置文件
create_default_config() {
    cat > "$CONFIG_FILE" << EOF
# 系统监控配置
DISK_WARNING=85
MEMORY_WARNING=90
LOAD_WARNING=1.5

# 要监控的服务列表
SERVICES=("sshd" "crond" "postfix")

# 邮件配置
ADMIN_EMAIL="$ADMIN_EMAIL"
EMAIL_SUBJECT_PREFIX="系统巡检"
EOF
    log_message "已创建默认配置文件: $CONFIG_FILE"
}

# 加载配置
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        log_error "配置文件不存在: $CONFIG_FILE"
        exit 1
    fi
}

# 检查磁盘使用情况
check_disk_usage() {
    log_message "检查磁盘使用情况..."
    
    local disk_warning=${DISK_WARNING:-85}
    local warning_found=false
    
    echo "<h3>📊 磁盘使用情况</h3>" >> "$HTML_REPORT"
    echo "<table border='1' style='border-collapse: collapse; width: 100%;'>" >> "$HTML_REPORT"
    echo "<tr><th>文件系统</th><th>容量</th><th>已用</th><th>可用</th><th>使用%</th><th>挂载点</th><th>状态</th></tr>" >> "$HTML_REPORT"
    
    df -h | tail -n +2 | while read -r filesystem size used avail percent mountpoint; do
        # 跳过特殊文件系统
        if [[ $filesystem =~ (tmpfs|devtmpfs|overlay) ]]; then
            continue
        fi
        
        usage_percent=$(echo "$percent" | tr -d '%')
        status_icon="✅"
        status_text="正常"
        
        if [ "$usage_percent" -ge "$disk_warning" ]; then
            status_icon="⚠️"
            status_text="警告"
            warning_found=true
            log_warning "磁盘使用率过高: $mountpoint ($usage_percent%)"
        fi
        
        echo "<tr><td>$filesystem</td><td>$size</td><td>$used</td><td>$avail</td><td>$percent</td><td>$mountpoint</td><td>$status_icon $status_text</td></tr>" >> "$HTML_REPORT"
    done
    
    echo "</table>" >> "$HTML_REPORT"
    
    if [ "$warning_found" = true ]; then
        return 1
    fi
    return 0
}

# 检查内存使用情况
check_memory_usage() {
    log_message "检查内存使用情况..."
    
    local memory_warning=${MEMORY_WARNING:-90}
    
    echo "<h3>💾 内存使用情况</h3>" >> "$HTML_REPORT"
    echo "<pre>" >> "$HTML_REPORT"
    free -h >> "$HTML_REPORT"
    echo "</pre>" >> "$HTML_REPORT"
    
    # 计算内存使用率
    local mem_info=$(free | grep Mem)
    local total_mem=$(echo "$mem_info" | awk '{print $2}')
    local used_mem=$(echo "$mem_info" | awk '{print $3}')
    local memory_usage=$((used_mem * 100 / total_mem))
    
    if [ "$memory_usage" -ge "$memory_warning" ]; then
        log_warning "内存使用率过高: $memory_usage%"
        return 1
    fi
    
    return 0
}

# 检查系统负载
check_system_load() {
    log_message "检查系统负载..."
    
    local load_warning=${LOAD_WARNING:-1.5}
    
    echo "<h3>📈 系统负载</h3>" >> "$HTML_REPORT"
    echo "<pre>" >> "$HTML_REPORT"
    uptime >> "$HTML_REPORT"
    echo "</pre>" >> "$HTML_REPORT"
    
    # 获取15分钟平均负载
    local load_15min=$(uptime | awk -F'load average:' '{print $2}' | awk -F, '{print $3}' | sed 's/ //g')
    
    # 获取CPU核心数
    local cpu_cores=$(nproc)
    local load_threshold=$(echo "$cpu_cores * $load_warning" | bc -l)
    
    if (( $(echo "$load_15min > $load_threshold" | bc -l) )); then
        log_warning "系统负载过高: $load_15min (阈值: $load_threshold)"
        return 1
    fi
    
    return 0
}

# 检查服务状态
check_services() {
    log_message "检查核心服务状态..."
    
    echo "<h3>🔧 服务状态检查</h3>" >> "$HTML_REPORT"
    echo "<table border='1' style='border-collapse: collapse; width: 100%;'>" >> "$HTML_REPORT"
    echo "<tr><th>服务名称</th><th>状态</th><th>操作</th></tr>" >> "$HTML_REPORT"
    
    local service_problems=0
    
    for service in "${SERVICES[@]}"; do
        if systemctl is-active --quiet "$service"; then
            status_icon="✅"
            status_text="运行中"
            action_button=""
        else
            status_icon="❌"
            status_text="未运行"
            action_button="<button style='background-color: #ff6b6b; color: white; border: none; padding: 5px 10px; cursor: pointer;' onclick='alert(\"需要手动启动服务: $service\")'>需要关注</button>"
            log_warning "服务未运行: $service"
            ((service_problems++))
        fi
        
        echo "<tr><td>$service</td><td>$status_icon $status_text</td><td>$action_button</td></tr>" >> "$HTML_REPORT"
    done
    
    echo "</table>" >> "$HTML_REPORT"
    
    if [ "$service_problems" -gt 0 ]; then
        return 1
    fi
    return 0
}

# 生成HTML报告头部
generate_html_header() {
    cat > "$HTML_REPORT" << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>系统巡检报告</title>
    <style>
        body { font-family: 'Microsoft YaHei', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 2px solid #4CAF50; padding-bottom: 10px; }
        h2 { color: #555; }
        h3 { color: #666; margin-top: 20px; }
        table { width: 100%; margin: 10px 0; border-collapse: collapse; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #4CAF50; color: white; }
        tr:hover { background-color: #f5f5f5; }
        .summary { background-color: #e8f5e8; padding: 15px; border-radius: 5px; margin: 20px 0; }
        pre { background-color: #f8f8f8; padding: 10px; border-radius: 5px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🖥️ 系统巡检报告</h1>
        <div class="summary">
            <h2>报告概要</h2>
            <p><strong>生成时间:</strong> $(date '+%Y年%m月%d日 %H:%M:%S')</p>
            <p><strong>主机名:</strong> $(hostname)</p>
            <p><strong>运行时间:</strong> $(uptime -p)</p>
        </div>
EOF
}

# 生成HTML报告尾部
generate_html_footer() {
    cat >> "$HTML_REPORT" << EOF
        <div class="summary">
            <h2>报告说明</h2>
            <p>本报告由自动化巡检脚本生成，如有问题请及时联系系统管理员。</p>
            <p>生成脚本: system_check.sh | 版本: 1.0</p>
        </div>
    </div>
</body>
</html>
EOF
}

# 发送邮件报告
send_email_report() {
    log_message "准备发送邮件报告..."
    
    if [ ! -f "$HTML_REPORT" ]; then
        log_error "HTML报告文件不存在: $HTML_REPORT"
        return 1
    fi
    
    # 检查邮件配置
    if ! command -v mailx &> /dev/null; then
        log_error "mailx 命令未找到，无法发送邮件"
        return 1
    fi
    
    # 发送邮件（这里使用mailx，实际环境可能需要配置SMTP）
    local email_body=$(cat "$HTML_REPORT")
    
    # 注意：这里需要根据你的邮件服务器配置进行调整
    # 以下是使用本地sendmail的示例
    echo "$email_body" | mail -s "$(echo -e "$EMAIL_SUBJECT\nContent-Type: text/html")" "$ADMIN_EMAIL"
    
    if [ $? -eq 0 ]; then
        log_message "邮件报告已发送至: $ADMIN_EMAIL"
    else
        log_error "邮件发送失败"
        return 1
    fi
}

# 主函数
main() {
    log_message "=== 开始执行系统巡检 ==="
    
    # 初始化
    initialize_checks
    load_config
    
    # 生成HTML报告头部
    generate_html_header
    
    # 执行各项检查
    local problems=0
    
    check_disk_usage || ((problems++))
    check_memory_usage || ((problems++))
    check_system_load || ((problems++))
    check_services || ((problems++))
    
    # 生成HTML报告尾部
    generate_html_footer
    
    # 发送邮件报告
    send_email_report
    
    # 总结报告
    if [ "$problems" -eq 0 ]; then
        log_message "✅ 所有检查项正常，系统运行良好"
        echo "<p style='color: green; font-weight: bold;'>✅ 所有系统检查项正常</p>" >> "$HTML_REPORT"
    else
        log_message "⚠️ 发现 $problems 个问题需要关注"
        echo "<p style='color: orange; font-weight: bold;'>⚠️ 发现 $problems 个问题需要关注，请查看详细报告</p>" >> "$HTML_REPORT"
    fi
    
    log_message "=== 系统巡检完成 ==="
    log_message "报告文件: $HTML_REPORT"
    log_message "日志文件: $LOG_FILE"
}

# 脚本入口
main "$@"
