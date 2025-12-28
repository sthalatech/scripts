#!/bin/bash
# RunPod Complete Setup Script
# Save as: /workspace/setup.sh
# Run once on new pod, then restart - everything works automatically

set -e

echo "🚀 RunPod Complete Setup Starting..."
echo "===================================="

# ============================================
# 1. Install Go to /workspace (persistent)
# ============================================
if [ ! -d "/workspace/go" ]; then
    echo "📦 Installing Go to /workspace..."
    cd /workspace
    wget -q https://go.dev/dl/go1.23.4.linux-amd64.tar.gz
    tar -xzf go1.23.4.linux-amd64.tar.gz
    rm go1.23.4.linux-amd64.tar.gz
    mkdir -p /workspace/go-projects/{bin,src,pkg}
    echo "✅ Go installed"
else
    echo "✅ Go already exists"
fi

# Set Go environment for this script
export GOROOT=/workspace/go
export GOPATH=/workspace/go-projects
export PATH=/workspace/go/bin:/workspace/go-projects/bin:/workspace/bin:$PATH

# ============================================
# 2. Install Ollama to /workspace (persistent)
# ============================================
if [ ! -f "/workspace/bin/ollama" ]; then
    echo "📦 Installing Ollama to /workspace..."
    mkdir -p /workspace/bin
    wget -q https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64 -O /workspace/bin/ollama
    chmod +x /workspace/bin/ollama
    echo "✅ Ollama installed"
else
    echo "✅ Ollama already exists"
fi

# ============================================
# 3. Clone scripts repo and build Go proxy
# ============================================
echo "📦 Cloning scripts repository..."
if [ -d "/workspace/scripts" ]; then
    cd /workspace/scripts
    git pull -q
else
    cd /workspace
    git clone -q https://github.com/sthalatech/scripts.git
fi

echo "🔨 Building Ollama proxy..."
cd /workspace/scripts
/workspace/go/bin/go build -o /workspace/bin/ollama-proxy main.go
echo "✅ Proxy built"

# Generate API key if not exists
if [ ! -f "/workspace/.api_key" ]; then
    API_KEY=$(openssl rand -hex 32)
    echo "$API_KEY" > /workspace/.api_key
    chmod 600 /workspace/.api_key
    echo "✅ Generated new API key: $API_KEY"
else
    API_KEY=$(cat /workspace/.api_key)
    echo "✅ Using existing API key: ${API_KEY:0:16}..."
fi

# ============================================
# 4. Create Supervisord config (persistent)
# ============================================
echo "📦 Setting up Supervisord..."
mkdir -p /workspace/supervisor/{conf.d,logs}

cat > /workspace/supervisor/supervisord.conf << 'EOSUPERVISOR'
[supervisord]
nodaemon=false
logfile=/workspace/supervisor/logs/supervisord.log
pidfile=/workspace/supervisor/supervisord.pid
childlogdir=/workspace/supervisor/logs

[unix_http_server]
file=/workspace/supervisor/supervisor.sock

[supervisorctl]
serverurl=unix:///workspace/supervisor/supervisor.sock

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[include]
files = /workspace/supervisor/conf.d/*.conf
EOSUPERVISOR

# Ollama service
cat > /workspace/supervisor/conf.d/ollama.conf << 'EOOLLAMACONF'
[program:ollama]
command=/workspace/bin/ollama serve
directory=/workspace
environment=OLLAMA_MODELS="/workspace/.ollama/models",OLLAMA_HOST="127.0.0.1:11434"
autostart=true
autorestart=true
startretries=3
stdout_logfile=/workspace/supervisor/logs/ollama.log
stderr_logfile=/workspace/supervisor/logs/ollama-error.log
user=root
EOOLLAMACONF

# Ollama proxy service
cat > /workspace/supervisor/conf.d/ollama-proxy.conf << EOPROXYCONF
[program:ollama-proxy]
command=/workspace/bin/ollama-proxy
directory=/workspace
environment=API_KEY=${API_KEY},OLLAMA_URL=http://localhost:11434,PORT=8000
autostart=true
autorestart=true
startretries=3
stdout_logfile=/workspace/supervisor/logs/ollama-proxy.log
stderr_logfile=/workspace/supervisor/logs/ollama-proxy-error.log
user=root
EOPROXYCONF

echo "✅ Supervisord configured"

# ============================================
# 5. Create startup script (persistent)
# ============================================
cat > /workspace/startup.sh << 'EOSTARTUP'
#!/bin/bash

# Export Go environment
export GOROOT=/workspace/go
export GOPATH=/workspace/go-projects
export PATH=/workspace/go/bin:/workspace/go-projects/bin:/workspace/bin:$PATH

# Start supervisord if not running
if ! pgrep supervisord > /dev/null; then
    # Install supervisor via pip (ephemeral, but fast ~2 seconds)
    pip install supervisor -q 2>/dev/null
    
    supervisord -c /workspace/supervisor/supervisord.conf 2>/dev/null
    sleep 2
    
    echo "=================================="
    echo "✅ Services Started"
    echo "=================================="
    supervisorctl -c /workspace/supervisor/supervisord.conf status
    echo ""
    echo "🔑 API Key: $(cat /workspace/.api_key 2>/dev/null || echo 'Not set')"
    echo "🌐 Expose port 8000 in RunPod dashboard"
    echo "🌐 Access: https://YOUR-POD-ID-8000.proxy.runpod.net"
    echo ""
    echo "📊 Management:"
    echo "   /workspace/manage status"
    echo "   /workspace/manage logs ollama"
    echo "   /workspace/manage apikey"
    echo ""
fi
EOSTARTUP

chmod +x /workspace/startup.sh

# ============================================
# 6. Configure .bashrc (auto-run startup)
# ============================================
cat > ~/.bashrc << 'EOBASHRC'
# Run startup script (Go paths + supervisor)
if [ -f /workspace/startup.sh ]; then
    source /workspace/startup.sh
fi
EOBASHRC

echo "✅ .bashrc configured"

# ============================================
# 7. Create management helper script
# ============================================
cat > /workspace/manage << 'EOMANAGE'
#!/bin/bash

case "$1" in
    status)
        echo "Services:"
        supervisorctl -c /workspace/supervisor/supervisord.conf status
        echo ""
        echo "Go:"
        /workspace/go/bin/go version 2>/dev/null || echo "  Go not in PATH (run: source /workspace/startup.sh)"
        ;;
    restart)
        supervisorctl -c /workspace/supervisor/supervisord.conf restart all
        ;;
    stop)
        supervisorctl -c /workspace/supervisor/supervisord.conf stop all
        ;;
    start)
        /workspace/startup.sh
        ;;
    logs)
        if [ -z "$2" ]; then
            echo "Available logs:"
            ls /workspace/supervisor/logs/*.log 2>/dev/null | xargs -n1 basename
            echo ""
            echo "Usage: /workspace/manage logs [service-name]"
            echo "Example: /workspace/manage logs ollama"
        else
            tail -f /workspace/supervisor/logs/${2}.log
        fi
        ;;
    shell)
        supervisorctl -c /workspace/supervisor/supervisord.conf
        ;;
    apikey)
        if [ -f /workspace/.api_key ]; then
            echo "API Key: $(cat /workspace/.api_key)"
        else
            echo "No API key found"
        fi
        ;;
    test)
        echo "Testing Ollama proxy..."
        API_KEY=$(cat /workspace/.api_key 2>/dev/null)
        if [ -z "$API_KEY" ]; then
            echo "❌ No API key found"
            exit 1
        fi
        curl -s -H "Authorization: Bearer $API_KEY" \
             http://localhost:8000/api/tags | head -20
        ;;
    pull)
        if [ -z "$2" ]; then
            echo "Usage: /workspace/manage pull [model-name]"
            echo "Example: /workspace/manage pull qwen2.5:32b-instruct-q4_K_M"
        else
            /workspace/bin/ollama pull "$2"
        fi
        ;;
    *)
        echo "RunPod Management Commands"
        echo ""
        echo "Usage: /workspace/manage [command]"
        echo ""
        echo "Commands:"
        echo "  status   - Show service status"
        echo "  start    - Start all services"
        echo "  stop     - Stop all services"
        echo "  restart  - Restart all services"
        echo "  logs     - View logs (e.g., logs ollama)"
        echo "  shell    - Open supervisorctl shell"
        echo "  apikey   - Show API key"
        echo "  test     - Test Ollama proxy"
        echo "  pull     - Pull Ollama model (e.g., pull qwen2.5:32b)"
        echo ""
        echo "Examples:"
        echo "  /workspace/manage status"
        echo "  /workspace/manage logs ollama-proxy"
        echo "  /workspace/manage pull qwen2.5:32b-instruct-q4_K_M"
        echo ""
        ;;
esac
EOMANAGE

chmod +x /workspace/manage

# ============================================
# 8. Create quick reference guide
# ============================================
cat > /workspace/README.txt << 'EOREADME'
RunPod Ollama Setup - Quick Reference
======================================

Services Running:
- Ollama: http://localhost:11434
- Ollama Proxy (with auth): http://localhost:8000

Management:
-----------
/workspace/manage status       # Check services
/workspace/manage logs ollama  # View logs
/workspace/manage apikey       # Show API key
/workspace/manage test         # Test proxy
/workspace/manage pull MODEL   # Download model

Pull Model:
-----------
/workspace/manage pull qwen2.5:32b-instruct-q4_K_M

Test API:
---------
API_KEY=$(cat /workspace/.api_key)
curl -H "Authorization: Bearer $API_KEY" \
     http://localhost:8000/api/tags

Expose Port:
------------
1. RunPod Dashboard → Your Pod → Edit
2. Add port: 8000
3. Access: https://YOUR-POD-ID-8000.proxy.runpod.net

External API Test:
------------------
curl -H "Authorization: Bearer $API_KEY" \
     https://YOUR-POD-ID-8000.proxy.runpod.net/api/generate \
     -d '{"model":"qwen2.5:32b-instruct-q4_K_M","prompt":"Hello","stream":false}'

Logs Location:
--------------
/workspace/supervisor/logs/ollama.log
/workspace/supervisor/logs/ollama-proxy.log

Auto-start:
-----------
Everything starts automatically on pod restart via .bashrc

Files:
------
/workspace/bin/ollama          - Ollama binary
/workspace/bin/ollama-proxy    - Auth proxy
/workspace/go                  - Go installation
/workspace/.api_key            - API key (keep secret!)
/workspace/startup.sh          - Startup script
/workspace/manage              - Management script
EOREADME

# ============================================
# 9. Test startup now
# ============================================
echo ""
echo "🧪 Testing startup..."
source /workspace/startup.sh

echo ""
echo "===================================="
echo "✅ Setup Complete!"
echo "===================================="
echo ""
echo "📝 What was installed:"
echo "   - Go: /workspace/go"
echo "   - Ollama: /workspace/bin/ollama"
echo "   - Ollama Proxy: /workspace/bin/ollama-proxy"
echo "   - Scripts: /workspace/scripts"
echo "   - Supervisor: /workspace/supervisor"
echo ""
echo "🔑 Your API Key:"
echo "   $(cat /workspace/.api_key)"
echo ""
echo "🔄 On every pod restart:"
echo "   - Services auto-start via .bashrc"
echo "   - Everything just works!"
echo ""
echo "📊 Quick commands:"
echo "   /workspace/manage status"
echo "   /workspace/manage logs ollama"
echo "   /workspace/manage pull qwen2.5:32b-instruct-q4_K_M"
echo "   /workspace/manage test"
echo ""
echo "🌐 Next steps:"
echo "   1. Expose port 8000 in RunPod dashboard"
echo "   2. Pull a model: /workspace/manage pull qwen2.5:32b-instruct-q4_K_M"
echo "   3. Test: /workspace/manage test"
echo ""
echo "📖 See /workspace/README.txt for full guide"
echo ""
