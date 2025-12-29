#!/bin/bash
# RunPod vLLM Setup Script
# https://github.com/sthalatech/scripts/runpod_setup.sh

set -e

# ============================================
# CONFIGURATION PARAMETERS
# ============================================
MODEL_NAME="Qwen/Qwen2.5-7B-Instruct"
MODEL_PATH="/workspace/models/Qwen2.5-7B-Instruct"
VLLM_PORT=8000
GO_VERSION="1.23.4"

echo "🚀 RunPod vLLM Setup Starting..."
echo "   Model: $MODEL_NAME"
echo "   Port: $VLLM_PORT"
echo "===================================="

# ============================================
# 0. Install system packages
# ============================================
echo "📦 Installing system packages..."
apt-get update -qq 2>/dev/null
apt-get install -y -qq nano lsof curl wget jq git python3-venv build-essential pip 2>/dev/null
echo "✅ System packages installed"

# ============================================
# 1. Create Python virtual environment (persistent)
# ============================================
if [ ! -d "/workspace/venv" ]; then
    echo "📦 Creating Python virtual environment..."
    python3 -m venv /workspace/venv
    source /workspace/venv/bin/activate
    pip install --upgrade pip
    echo "✅ Virtual environment created"
else
    echo "✅ Virtual environment exists"
    source /workspace/venv/bin/activate
fi

# ============================================
# 2. Install supervisor in venv (persistent)
# ============================================
echo "📦 Installing supervisor..."
pip install supervisor
echo "✅ Supervisor installed"

# ============================================
# 3. Install Go in venv (persistent)
# ============================================
if [ ! -d "/workspace/venv/go" ]; then
    echo "📦 Installing Go $GO_VERSION..."
    cd /workspace/venv
    wget -q https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
    tar -xzf go${GO_VERSION}.linux-amd64.tar.gz
    rm go${GO_VERSION}.linux-amd64.tar.gz
    echo "✅ Go installed"
else
    echo "✅ Go exists"
fi

export GOROOT=/workspace/venv/go
export GOPATH=/workspace/venv/go-projects
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
mkdir -p $GOPATH/{bin,src,pkg}

# ============================================
# 4. Install vLLM and dependencies (persistent)
# ============================================
echo "📦 Installing vLLM..."
pip install vllm huggingface-hub hf_transfer
echo "✅ vLLM installed"

# ============================================
# 5. Download model (persistent)
# ============================================
if [ ! -d "$MODEL_PATH" ]; then
    echo "📦 Downloading model $MODEL_NAME..."
    mkdir -p $(dirname "$MODEL_PATH")
    export HF_HOME=/workspace/.cache/huggingface
    export HF_HUB_ENABLE_HF_TRANSFER=1
    hf download $MODEL_NAME --local-dir "$MODEL_PATH"
    echo "✅ Model downloaded to $MODEL_PATH"
else
    echo "✅ Model exists at $MODEL_PATH"
fi

# ============================================
# 6. Build Go proxy (vLLM API authentication)
# ============================================
echo "📦 Setting up vLLM auth proxy..."
if [ -d "/workspace/scripts" ]; then
    cd /workspace/scripts && git pull -q
else
    cd /workspace && git clone -q https://github.com/sthalatech/scripts.git
fi

cd /workspace/scripts
$GOROOT/bin/go build -o /workspace/venv/bin/vllm-auth-proxy vllm-auth-proxy.go
echo "✅ Auth proxy built"

# Generate API key
if [ ! -f "/workspace/.api_key" ]; then
    API_KEY=$(openssl rand -hex 32)
    echo "$API_KEY" > /workspace/.api_key
    chmod 600 /workspace/.api_key
    echo "✅ API key generated: $API_KEY"
else
    API_KEY=$(cat /workspace/.api_key)
    echo "✅ API key exists: ${API_KEY:0:16}..."
fi

# ============================================
# 7. Supervisord configuration
# ============================================
echo "📦 Configuring supervisord..."
mkdir -p /workspace/supervisor/{conf.d,logs}

cat > /workspace/supervisor/supervisord.conf << 'EOF'
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
EOF

# vLLM service (localhost only - internal)
cat > /workspace/supervisor/conf.d/vllm.conf << VLLMEOF
[program:vllm]
command=/workspace/venv/bin/vllm serve $MODEL_PATH --host 127.0.0.1 --port 11434 --dtype auto
directory=/workspace
environment=HF_HOME="/workspace/.cache/huggingface",CUDA_VISIBLE_DEVICES="0"
autostart=true
autorestart=true
startretries=3
stdout_logfile=/workspace/supervisor/logs/vllm.log
stderr_logfile=/workspace/supervisor/logs/vllm-error.log
user=root
VLLMEOF

# vLLM auth proxy service (0.0.0.0 - public with auth)
# IMPORTANT: Use 127.0.0.1 (not localhost) to avoid IPv6 issues
cat > /workspace/supervisor/conf.d/vllm-auth-proxy.conf << PROXYEOF
[program:vllm-auth-proxy]
command=/workspace/venv/bin/vllm-auth-proxy
directory=/workspace
environment=API_KEY=${API_KEY},VLLM_URL=http://127.0.0.1:11434,BIND_HOST=0.0.0.0,PORT=${VLLM_PORT}
autostart=true
autorestart=true
startretries=3
stdout_logfile=/workspace/supervisor/logs/vllm-auth-proxy.log
stderr_logfile=/workspace/supervisor/logs/vllm-auth-proxy-error.log
user=root
PROXYEOF

echo "✅ Supervisord configured"

# ============================================
# 8. Startup script (auto-runs on pod restart)
# ============================================
cat > /workspace/startup.sh << 'STARTUPEOF'
#!/bin/bash

# Install missing packages
PACKAGES="nano lsof curl wget jq"
MISSING=""
for pkg in $PACKAGES; do
    command -v $pkg &>/dev/null || MISSING="$MISSING $pkg"
done
[ -n "$MISSING" ] && apt-get update -qq && apt-get install -y -qq $MISSING

# Activate virtual environment
if [ -f /workspace/venv/bin/activate ]; then
    source /workspace/venv/bin/activate
    export GOROOT=/workspace/venv/go
    export GOPATH=/workspace/venv/go-projects
    export PATH=$GOROOT/bin:$GOPATH/bin:/workspace/venv/bin:$PATH
else
    echo "❌ Virtual environment not found"
    exit 1
fi

# Start supervisord
if ! pgrep supervisord >/dev/null; then
    echo "🚀 Starting vLLM services..."
    supervisord -c /workspace/supervisor/supervisord.conf
    sleep 3
    supervisorctl -c /workspace/supervisor/supervisord.conf status
    echo ""
    echo "=================================="
    echo "✅ vLLM Services Running"
    echo "=================================="
    echo "🔑 API Key: $(cat /workspace/.api_key 2>/dev/null)"
    echo "🔒 vLLM: http://127.0.0.1:11434 (internal only)"
    echo "🌐 Proxy: http://0.0.0.0:VLLM_PORT (public with auth)"
    echo "📊 Management: /workspace/manage status"
    echo "🧪 Test: /workspace/manage test"
    echo ""
else
    echo "✅ Supervisor already running"
fi
STARTUPEOF

sed -i "s/VLLM_PORT/${VLLM_PORT}/g" /workspace/startup.sh
chmod +x /workspace/startup.sh

# ============================================
# 9. Auto-start configuration
# ============================================
cat > ~/.bashrc << 'EOF'
# Auto-start vLLM on login
if [ -f /workspace/startup.sh ]; then
    source /workspace/startup.sh
fi
EOF

echo "✅ Auto-start configured"

# ============================================
# 10. Management helper script
# ============================================
cat > /workspace/manage << 'MANAGEEOF'
#!/bin/bash

# Activate venv
source /workspace/venv/bin/activate 2>/dev/null

# Ensure supervisor is running
ensure_supervisor() {
    if ! pgrep supervisord >/dev/null; then
        echo "⚠️  Starting supervisord..."
        supervisord -c /workspace/supervisor/supervisord.conf
        sleep 2
    fi
}

case "$1" in
    status)
        ensure_supervisor
        echo "Services:"
        supervisorctl -c /workspace/supervisor/supervisord.conf status
        echo ""
        echo "GPU:"
        nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader 2>/dev/null || echo "  nvidia-smi unavailable"
        ;;
    restart)
        ensure_supervisor
        supervisorctl -c /workspace/supervisor/supervisord.conf restart all
        ;;
    stop)
        ensure_supervisor
        supervisorctl -c /workspace/supervisor/supervisord.conf stop all
        ;;
    start)
        /workspace/startup.sh
        ;;
    logs)
        SERVICE=${2:-vllm}
        if [ "$SERVICE" = "proxy" ]; then
            SERVICE="vllm-auth-proxy"
        fi
        tail -f /workspace/supervisor/logs/${SERVICE}.log
        ;;
    shell)
        ensure_supervisor
        supervisorctl -c /workspace/supervisor/supervisord.conf
        ;;
    apikey)
        cat /workspace/.api_key 2>/dev/null || echo "API key not found"
        ;;
    test)
        echo "Testing vLLM API..."
        API_KEY=$(cat /workspace/.api_key 2>/dev/null)
        if [ -z "$API_KEY" ]; then
            echo "❌ API key not found"
            exit 1
        fi
        
        echo "Sending chat completion request..."
        curl -s -H "Authorization: Bearer $API_KEY" \
             -H "Content-Type: application/json" \
             http://127.0.0.1:VLLM_PORT/v1/chat/completions \
             -d '{
               "model": "MODEL_PATH_PLACEHOLDER",
               "messages": [{"role": "user", "content": "Hello! Respond with a short greeting."}],
               "max_tokens": 50
             }' | jq -r '.choices[0].message.content' 2>/dev/null || echo "Response received (install jq for formatting)"
        ;;
    models)
        curl -s http://127.0.0.1:VLLM_PORT/v1/models | jq . 2>/dev/null || curl -s http://127.0.0.1:VLLM_PORT/v1/models
        ;;
    *)
        echo "RunPod vLLM Management"
        echo ""
        echo "Usage: /workspace/manage [command]"
        echo ""
        echo "Commands:"
        echo "  status          - Show service status and GPU usage"
        echo "  start           - Start all services"
        echo "  stop            - Stop all services"
        echo "  restart         - Restart all services"
        echo "  logs [service]  - View logs (vllm, proxy)"
        echo "  shell           - Open supervisorctl shell"
        echo "  apikey          - Show API key"
        echo "  test            - Test vLLM API"
        echo "  models          - List available models"
        echo ""
        echo "Examples:"
        echo "  /workspace/manage status"
        echo "  /workspace/manage logs vllm"
        echo "  /workspace/manage test"
        ;;
esac
MANAGEEOF

sed -i "s/VLLM_PORT/${VLLM_PORT}/g" /workspace/manage
sed -i "s|MODEL_PATH_PLACEHOLDER|${MODEL_PATH}|g" /workspace/manage
chmod +x /workspace/manage

# ============================================
# 11. README
# ============================================
cat > /workspace/README.txt << READMEEOF
RunPod vLLM Setup - Quick Reference
====================================

Configuration:
- Model: $MODEL_NAME
- Location: $MODEL_PATH
- vLLM Port: 11434 (127.0.0.1 only - internal)
- Proxy Port: $VLLM_PORT (0.0.0.0 - public with auth)

Security:
- vLLM runs on 127.0.0.1 (not exposed)
- Only authenticated proxy is publicly accessible
- All requests must include API key

Management:
-----------
/workspace/manage status       # Check services & GPU
/workspace/manage logs vllm    # View vLLM logs
/workspace/manage logs proxy   # View proxy logs
/workspace/manage apikey       # Show API key
/workspace/manage test         # Test API
/workspace/manage models       # List models

API Usage (Local):
------------------
API_KEY=\$(cat /workspace/.api_key)

curl -H "Authorization: Bearer \$API_KEY" \\
     -H "Content-Type: application/json" \\
     http://127.0.0.1:${VLLM_PORT}/v1/chat/completions \\
     -d '{
       "model": "$MODEL_PATH",
       "messages": [{"role": "user", "content": "Hello!"}],
       "max_tokens": 100
     }'

Expose Port in RunPod:
----------------------
1. RunPod Dashboard → Your Pod → Edit
2. Add port: ${VLLM_PORT}
3. Access: https://YOUR-POD-ID-${VLLM_PORT}.proxy.runpod.net

External API Usage:
-------------------
curl -H "Authorization: Bearer \$API_KEY" \\
     -H "Content-Type: application/json" \\
     https://YOUR-POD-ID-${VLLM_PORT}.proxy.runpod.net/v1/chat/completions \\
     -d '{
       "model": "$MODEL_PATH",
       "messages": [{"role": "user", "content": "Hello!"}]
     }'

Files:
------
/workspace/venv                     - Python + Go environment
/workspace/models                   - Downloaded models
/workspace/venv/bin/vllm-auth-proxy - Authentication proxy
/workspace/.api_key                 - API key (keep secret!)
/workspace/supervisor               - Service configs
/workspace/startup.sh               - Auto-start script
/workspace/manage                   - Management CLI

Auto-start:
-----------
Services start automatically on pod restart via .bashrc
READMEEOF

# ============================================
# 12. Start services now
# ============================================
echo ""
echo "🧪 Starting services..."
source /workspace/startup.sh

echo ""
echo "===================================="
echo "✅ Setup Complete!"
echo "===================================="
echo ""
echo "📝 Security Setup:"
echo "   - vLLM: 127.0.0.1:11434 (internal only)"
echo "   - Proxy: 0.0.0.0:$VLLM_PORT (public with auth)"
echo ""
echo "🔑 API Key: $(cat /workspace/.api_key)"
echo ""
echo "📊 Commands:"
echo "   /workspace/manage status"
echo "   /workspace/manage test"
echo "   /workspace/manage logs vllm"
echo ""
echo "🌐 Expose port $VLLM_PORT in RunPod dashboard"
echo "📖 Full guide: cat /workspace/README.txt"
echo ""
