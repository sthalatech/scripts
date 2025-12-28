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
