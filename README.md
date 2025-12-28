# RunPod Ollama Setup

Complete automated setup for running Ollama with authentication on RunPod GPU pods.

## 🚀 Quick Start (New Pod)

Run this single command on your new RunPod pod:
```bash
curl -fsSL https://raw.githubusercontent.com/sthalatech/scripts/main/runpod_setup.sh | bash
```

**Or using wget:**
```bash
wget -qO- https://raw.githubusercontent.com/sthalatech/scripts/main/runpod_setup.sh | bash
```

That's it! The script will:
- ✅ Install Go to `/workspace` (persistent)
- ✅ Install Ollama to `/workspace` (persistent)
- ✅ Build the authentication proxy
- ✅ Generate API key
- ✅ Configure auto-start on pod restarts
- ✅ Start all services

---

## 📋 What Gets Installed

### Persistent (survives pod restarts):
- Go 1.23.4 in `/workspace/go`
- Ollama binary in `/workspace/bin/ollama`
- Authentication proxy in `/workspace/bin/ollama-proxy`
- Supervisor configs in `/workspace/supervisor`
- API key in `/workspace/.api_key`

### Ephemeral (reinstalled automatically on restart):
- System packages: nano, lsof, curl, wget, jq
- Python supervisor package

---

## 🔑 API Key

Your API key is automatically generated and saved to `/workspace/.api_key`

View it anytime:
```bash
/workspace/manage apikey
```

---

## 📊 Management Commands
```bash
/workspace/manage status       # Check service status
/workspace/manage logs ollama  # View Ollama logs
/workspace/manage logs ollama-proxy  # View proxy logs
/workspace/manage apikey       # Show API key
/workspace/manage test         # Test the proxy
/workspace/manage pull MODEL   # Pull Ollama model
/workspace/manage restart      # Restart all services
/workspace/manage stop         # Stop all services
/workspace/manage start        # Start all services
```

---

## 🌐 Expose Port (Access from Internet)

1. Go to **RunPod Dashboard** → Your Pod → **Edit Pod**
2. Find **"Expose HTTP Ports"** section
3. Add port: **8000**
4. Click **Save**
5. Copy your public URL: `https://YOUR-POD-ID-8000.proxy.runpod.net`

---

## 📥 Pull a Model
```bash
# Pull Qwen 2.5 32B (recommended for RTX 4000 Ada)
/workspace/manage pull qwen2.5:32b-instruct-q4_K_M

# Or other models
/workspace/manage pull llama3.3:70b-instruct-q4_K_M
/workspace/manage pull qwen2.5:14b
```

---

## 🧪 Test the API

### Local test:
```bash
/workspace/manage test
```

### Manual test:
```bash
API_KEY=$(cat /workspace/.api_key)

# List models
curl -H "Authorization: Bearer $API_KEY" \
     http://localhost:8000/api/tags

# Generate text
curl -H "Authorization: Bearer $API_KEY" \
     http://localhost:8000/api/generate \
     -d '{"model":"qwen2.5:32b-instruct-q4_K_M","prompt":"Hello","stream":false}'
```

### External test (after exposing port):
```bash
API_KEY=$(cat /workspace/.api_key)

curl -H "Authorization: Bearer $API_KEY" \
     https://YOUR-POD-ID-8000.proxy.runpod.net/api/generate \
     -d '{"model":"qwen2.5:32b-instruct-q4_K_M","prompt":"Hello","stream":false}'
```

---

## 🔄 Auto-Start on Pod Restart

Everything starts automatically! When you restart your pod:

1. SSH in
2. Wait ~10 seconds
3. Services are running

Check status:
```bash
/workspace/manage status
```

---

## 📝 Services

| Service | Port | Description |
|---------|------|-------------|
| Ollama | 11434 | Ollama server (internal) |
| Ollama Proxy | 8000 | Authenticated API (expose this) |

---

## 🗂️ File Locations
```
/workspace/
├── bin/
│   ├── ollama              # Ollama binary
│   └── ollama-proxy        # Auth proxy binary
├── go/                     # Go installation
├── scripts/                # This repo (cloned)
├── supervisor/             # Supervisor configs
│   ├── supervisord.conf
│   ├── conf.d/
│   │   ├── ollama.conf
│   │   └── ollama-proxy.conf
│   └── logs/
│       ├── ollama.log
│       └── ollama-proxy.log
├── .api_key               # Your API key (keep secret!)
├── .ollama/               # Ollama models
├── startup.sh             # Auto-start script
├── manage                 # Management script
└── README.txt             # Quick reference
```

---

## 🐛 Troubleshooting

### Services not running?
```bash
/workspace/manage start
```

### Check logs:
```bash
/workspace/manage logs ollama
/workspace/manage logs ollama-proxy
```

### Restart services:
```bash
/workspace/manage restart
```

### Manual startup:
```bash
source /workspace/startup.sh
```

---

## 💰 Cost Optimization

**Recommended setup for $50/month budget:**
- RTX 4000 Ada spot instance @ $0.19/hr
- Run 5 hours/day = $28.50/month
- Auto-start/stop via RunPod automation or GitHub Actions

See the automation scripts in this repo for scheduling.

---

## 🔒 Security

- API key is required for all requests
- Use `Authorization: Bearer YOUR_API_KEY` header
- API key stored in `/workspace/.api_key` (600 permissions)
- Ollama itself is NOT exposed (proxy only)

---

## 📚 Additional Resources

- [Ollama Documentation](https://github.com/ollama/ollama)
- [RunPod Documentation](https://docs.runpod.io/)
- [Ollama Models](https://ollama.com/library)

---

## 🤝 Contributing

Issues and PRs welcome!

---

## 📄 License

MIT
