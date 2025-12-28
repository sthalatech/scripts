#!/bin/bash

# RunPod Ollama Setup Script - Persistent Installation
# Save this as: /workspace/setup_ollama.sh

echo "🚀 Setting up Ollama on RunPod..."

# Install Ollama to /workspace (persistent storage)
if [ ! -f /usr/local/bin/ollama ]; then
    echo "📦 Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
else
    echo "✅ Ollama already installed"
fi

# Configure environment variables
export OLLAMA_MODELS=/workspace/.ollama/models
export OLLAMA_HOST=0.0.0.0:11434

# Create models directory
mkdir -p /workspace/.ollama/models

# Add to bashrc for persistence
if ! grep -q "OLLAMA_MODELS" ~/.bashrc; then
    echo "📝 Configuring environment..."
    cat >> ~/.bashrc << 'EOF'
export OLLAMA_MODELS=/workspace/.ollama/models
export OLLAMA_HOST=0.0.0.0:11434
export PATH=/usr/local/bin:$PATH
EOF
fi

source ~/.bashrc

# Start Ollama server
echo "🔥 Starting Ollama server..."
pkill ollama 2>/dev/null
nohup ollama serve > /tmp/ollama.log 2>&1 &

sleep 3

# Install Go
cd /workspace
wget https://go.dev/dl/go1.23.4.linux-amd64.tar.gz
tar -xzf go1.23.4.linux-amd64.tar.gz 
rm go1.23.4.linux-amd64.tar.gz 
echo 'export GOROOT=/workspace/go' >> ~/.bashrc 
echo 'export GOPATH=/workspace/go-projects' >> ~/.bashrc 
echo 'export PATH=$GOROOT/bin:$GOPATH/bin:$PATH' >> ~/.bashrc 
source ~/.bashrc 
mkdir -p /workspace/go-projects/{bin,src,pkg} 
echo "GO Installed"
go version
mkdir -p /workspace/ollama-proxy && cd /workspace/ollama-proxy
curl -o main.go https://raw.githubusercontent.com/sthalatech/scripts/refs/heads/main/main.go
go mod init ollama-proxy && go build -o ollama-proxy

go mod tidy && go build -o ollama-proxy

#Generate API Key
# Generate a secure API key
API_KEY=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
echo "Generated API key: $API_KEY"

# Install supervisord
pip install supervisor

# Create config directory
mkdir -p /workspace/supervisor/conf.d /workspace/supervisor/logs

# Create supervisord config
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

# Create Ollama service config
cat > /workspace/supervisor/conf.d/ollama.conf << 'EOF'
[program:ollama]
command=/usr/local/bin/ollama serve
directory=/workspace
environment=OLLAMA_MODELS="/workspace/.ollama/models",OLLAMA_HOST="127.0.0.1:11434"
autostart=true
autorestart=true
startretries=3
stdout_logfile=/workspace/supervisor/logs/ollama.log
stderr_logfile=/workspace/supervisor/logs/ollama_error.log
user=root
EOF

# Create Ollama Proxy service config
cat > /workspace/supervisor/conf.d/ollama-proxy.conf << 'EOF'
[program:ollama-proxy]
command=/workspace/ollama-proxy/ollama-proxy
directory=/workspace
environment=API_KEY="$API_KEY"
autostart=true
autorestart=true
startretries=3
stdout_logfile=/workspace/supervisor/logs/ollama-proxy.log
stderr_logfile=/workspace/supervisor/logs/ollama-proxy-error.log
user=root
EOF

supervisorctl reread && supervisorctl update

# Control services
supervisorctl -c /workspace/supervisor/supervisord.conf status
# supervisorctl -c /workspace/supervisor/supervisord.conf start ollama
# supervisorctl -c /workspace/supervisor/supervisord.conf stop ollama
# supervisorctl -c /workspace/supervisor/supervisord.conf restart ollama

# Pull recommended model
echo "📥 Pulling Qwen2.5 32B model..."
ollama pull qwen2.5:32b-instruct-q4_K_M

echo ""
echo "=================================="
echo "✅ Ollama Setup Complete!"
echo "=================================="
echo ""
echo "📊 Model stored in: /workspace/.ollama/models"
echo "🌐 API available at: http://0.0.0.0:11434"
echo ""
echo "🧪 Test it:"
echo "   ollama run qwen2.5:32b-instruct-q4_K_M"
echo ""
echo "📝 Check logs:"
echo "   tail -f /tmp/ollama.log"
echo ""
