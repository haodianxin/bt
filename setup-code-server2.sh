#!/bin/bash
# ============================================================
# code-server 一键安装脚本
# 功能：安装 code-server + 配置 nginx 反向代理 + pm2 守护进程
# 访问地址：http://<IP>:5700/coder/
# 密码：wswhaaa
# ============================================================

set -e

# --- 配置区（按需修改） ---
CS_PORT=7862
CS_PASSWORD="wswhaaa"
NGINX_CONF="/etc/nginx/conf.d/apps.conf"
NGINX_PORT=5700

# --- 颜色输出 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- 检查依赖 ---
check_deps() {
    info "检查依赖..."
    for cmd in nginx pm2 curl; do
        command -v $cmd >/dev/null 2>&1 || error "未找到 $cmd，请先安装"
    done
    info "依赖检查通过 ✓"
}

# --- 安装 code-server ---
install_code_server() {
    if command -v code-server >/dev/null 2>&1; then
        warn "code-server 已安装，跳过安装步骤"
        code-server --version
        return
    fi

    info "获取 code-server 最新版本..."
    local VERSION
    VERSION=$(curl -s https://api.github.com/repos/coder/code-server/releases/latest | grep -oP '"tag_name":\s*"v\K[^"]+')
    [ -z "$VERSION" ] && error "获取版本号失败"

    local DEB_URL="https://github.com/coder/code-server/releases/download/v${VERSION}/code-server_${VERSION}_amd64.deb"
    local DEB_FILE="/tmp/code-server_${VERSION}_amd64.deb"

    info "下载 code-server v${VERSION} ..."
    curl -fSL "$DEB_URL" -o "$DEB_FILE" || error "下载失败"

    info "安装中..."
    dpkg -i "$DEB_FILE" || apt-get install -f -y
    rm -f "$DEB_FILE"

    info "code-server v${VERSION} 安装成功 ✓"
}

# --- 配置 nginx ---
setup_nginx() {
    # 检查是否已配置
    if grep -q "upstream codeServer" "$NGINX_CONF" 2>/dev/null; then
        warn "nginx 已配置 codeServer upstream，跳过"
        return
    fi

    info "配置 nginx 反向代理..."

    # 备份原配置
    cp "$NGINX_CONF" "${NGINX_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    info "原配置已备份"

    # 插入 upstream codeServer（在 webServer upstream 之后）
    sed -i '/^upstream webServer/,/^}/{
/^}/a\
upstream codeServer {\
  server 0.0.0.0:'"$CS_PORT"';\
}
}' "$NGINX_CONF"

    # 在 gzip_http_version 之后插入 location /coder/
    sed -i '/gzip_http_version/a\
\
        location /coder/ {\
            proxy_pass http://codeServer/;\
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\
            proxy_set_header Host $http_host;\
            proxy_set_header X-NginX-Proxy true;\
            proxy_http_version 1.1;\
            proxy_set_header Upgrade $http_upgrade;\
            proxy_set_header Connection "upgrade";\
            proxy_set_header X-Real-IP $remote_addr;\
            proxy_buffering off;\
            proxy_redirect default;\
            proxy_connect_timeout 1800;\
            proxy_send_timeout 1800;\
            proxy_read_timeout 1800;\
        }' "$NGINX_CONF"

    # 验证配置
    nginx -t 2>&1 || error "nginx 配置验证失败！已备份原配置，请手动检查"

    info "nginx 配置完成 ✓"
}

# --- 启动 code-server ---
start_code_server() {
    info "停止旧的 code-server 进程..."
    pm2 delete code-server 2>/dev/null || true

    info "通过 pm2 启动 code-server..."
    export PASSWORD="$CS_PASSWORD"
    pm2 start "code-server --bind-addr 0.0.0.0:${CS_PORT} --port ${CS_PORT} --auth password" \
        --name "code-server"

    pm2 save 2>/dev/null || true

    info "等待服务启动..."
    sleep 3

    # 验证端口
    if ss -tlnp | grep -q ":${CS_PORT}"; then
        info "code-server 启动成功，监听端口 ${CS_PORT} ✓"
    else
        error "code-server 启动失败，请检查 pm2 logs code-server"
    fi
}

# --- 重载 nginx ---
reload_nginx() {
    info "重载 nginx..."
    nginx -s reload
    info "nginx 重载完成 ✓"
}

# --- 输出访问信息 ---
print_info() {
    local IP
    IP=$(curl -s http://ifconfig.me 2>/dev/null || echo "<你的服务器IP>")

    echo ""
    echo "============================================"
    echo -e "${GREEN}  code-server 部署完成！${NC}"
    echo "============================================"
    echo ""
    echo "  版本:    $(code-server --version 2>/dev/null || echo '未知')"
    echo "  密码:    ${CS_PASSWORD}"
    echo ""
    echo "  直接访问: http://${IP}:${CS_PORT}"
    echo "  代理访问: http://${IP}:${NGINX_PORT}/coder/"
    echo ""
    echo "  常用命令:"
    echo "    pm2 logs code-server    # 查看日志"
    echo "    pm2 restart code-server # 重启服务"
    echo "    pm2 stop code-server    # 停止服务"
    echo "============================================"
}

# --- 主流程 ---
main() {
    echo ""
    echo "================= code-server 一键安装 ================="
    echo ""
    check_deps
    install_code_server
    setup_nginx
    start_code_server
    reload_nginx
    print_info
}

main "$@"
