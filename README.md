# scripts

Automated setup and auth proxy for running Ollama on RunPod GPU pods.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/sthalatech/scripts/refs/heads/main/runpod_setup.sh | bash
```

Installs Go and Ollama into `/workspace` (persistent across pod restarts), builds the authentication proxy, generates an API key, and configures auto-start.

## Usage

```bash
/workspace/manage status
/workspace/manage pull qwen2.5:32b-instruct-q4_K_M
/workspace/manage apikey
```

The proxy exposes an authenticated Ollama API on port 8000 (`Authorization: Bearer $API_KEY`); Ollama itself (port 11434) is never exposed directly. See `/workspace/manage` for the full command list (logs, restart, test).

## Contributing

Issues and PRs are welcome. For significant changes, please open an issue first to discuss what you'd like to change.

## Reporting Issues

Found a bug or have a feature request? [Open an issue](../../issues/new) with steps to reproduce (or the use case, for feature requests).

## License

MIT © Sthala
