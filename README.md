# Self-hosted LLM for coding in VS Code

Two backends are available:

- **llama.cpp** (default): `Dockerfile.llamacpp` + `docker-compose.llamacpp.yml`. One server for chat (port 8013), one for autocomplete (port 8012).
- **Ollama**: `Dockerfile` + `docker-compose.yml`. One server for both (port 11434). See [Using Ollama instead](#using-ollama-instead).

The agent is **Claude Code** or **Hermes Agent**, talking to the chat server.

## Setup

Run each step in a WSL terminal, from the repo folder (`~/ollama-agent`).

### 1. Give WSL more memory

The chat model needs ~20 GB of RAM, and WSL only gets half of the Windows RAM by default. In `C:\Users\<you>\.wslconfig`, under `[wsl2]`, add (adjust to leave Windows ~8 GB):

```bash
printf '\nmemory=24GB\nswap=8GB\n' >> /mnt/c/Users/<you>/.wslconfig
```

If the file doesn't exist or has no `[wsl2]` line, add `[wsl2]` above these lines. Then restart WSL from **PowerShell** (VS Code loses its WSL connection, reopen the folder after):

```powershell
wsl --shutdown
```

Check: `free -g` shows ~23 in the `total` column.

### 2. Install Docker Compose

```bash
sudo apt-get install -y docker-compose-v2
```

Check: `docker compose version` prints a version. When asked, enter your WSL password (nothing appears while you type). If you forgot it, reset it from PowerShell with `wsl -u root passwd <wsl-user>`.

### 3. Let Docker use the GPU (one time)

```bash
bash scripts/install-nvidia-toolkit.sh
```

Done when it prints a table showing your GPU. Skip this step for CPU only.

### 4. Create `.env`

```bash
cat > .env <<'EOF'
LLAMACPP_CHAT_PORT=8013
LLAMACPP_AUTOCOMPLETE_PORT=8012
WEBUI_PORT=3000
LLAMACPP_CHAT_MODEL=unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF:Q4_K_M
LLAMACPP_AUTOCOMPLETE_MODEL=ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF:Q8_0
LLAMACPP_CONTEXT_LENGTH=65536
LLAMACPP_CHAT_N_CPU_MOE=40
EOF
```

The models are Hugging Face GGUF (`repo:quant`), downloaded on the first start.

Qwen3-Coder 30B-A3B is a mixture-of-experts model (~18 GB, 3B active per token) with native tool calling, needed for the agents to edit files and run commands. It doesn't fit in VRAM, so `LLAMACPP_CHAT_N_CPU_MOE` keeps that many of its 48 expert layers in RAM. 40 is a starting point for 8 GB of VRAM; use ~44 for 6 GB. Step 6 says how to tune it.

Both agents send a large system prompt and tool list on every request: Hermes needs at least 64k tokens of context, and Claude Code doesn't fit in 32k. The KV cache takes ~3 GB of VRAM at 64k.

`bartowski/Qwen2.5-Coder-7B-Instruct-GGUF:Q4_K_M` is a smaller alternative that fits fully in VRAM, but it writes tool calls as text, so the agents can't run them.

### 5. Build and start the servers

```bash
docker compose -f docker-compose.llamacpp.yml build --pull
docker compose -f docker-compose.llamacpp.yml up -d
```

`--pull` matters: the Anthropic endpoint Claude Code uses only exists in llama.cpp images from 2026 or later.

CPU only: add `-f docker-compose.llamacpp.cpu.yml` after `-f docker-compose.llamacpp.yml` in both commands. Optional chat UI on <http://localhost:3000>: add `--profile ui` to the `up` command.

### 6. Wait for the model to load

The first start downloads ~18 GB.

```bash
docker logs -f llamacpp-chat
```

Wait for `model loaded` (then `listening on ...`), then Ctrl+C. Check: `curl http://localhost:8013/health` returns `{"status":"ok"}`. Autocomplete logs: `docker logs -f llamacpp-autocomplete`.

Tuning `LLAMACPP_CHAT_N_CPU_MOE` (edit `.env`, then run `docker compose -f docker-compose.llamacpp.yml up -d` again):

- Out of memory error in the logs, or very slow generation (a few tokens/s, VRAM overflowing): raise it.
- `nvidia-smi` shows a lot of free VRAM while `llama-server` runs: lower it for speed.

Autocomplete runs on the CPU (`--n-gpu-layers "0"`) to leave the VRAM to the chat model.

### 7. Test the endpoint

```bash
curl http://localhost:8013/v1/messages -H 'content-type: application/json' \
  -d '{"model":"qwen3-coder-30b","max_tokens":32,"messages":[{"role":"user","content":"hi"}]}'
```

You get a JSON reply with some text. A 503 `Loading model` means the model is still loading: wait for step 6. A 404 means the image is too old: redo step 5.

### 8. Install the agent

Pick one. Each llama.cpp server runs a single model, so the model name is only a label.

#### Claude Code

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Open a new terminal, then:

```bash
export ANTHROPIC_BASE_URL=http://localhost:8013
export ANTHROPIC_AUTH_TOKEN=none
export ANTHROPIC_MODEL=qwen3-coder-30b
export ANTHROPIC_DEFAULT_HAIKU_MODEL=qwen3-coder-30b
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
claude
```

No `/v1` in the base URL: Claude Code appends `/v1/messages` itself. `ANTHROPIC_AUTH_TOKEN` skips the login (llama-server ignores it). The Haiku model is used for background tasks (titles, summaries), so it points at the same server.

Keep these in the shell session rather than in `~/.claude/settings.json` or `~/.bashrc`, otherwise every Claude Code session on the machine goes to the local model. For the VS Code extension (`code --install-extension anthropic.claude-code`), put the same variables in an `env` block of the project's `.claude/settings.local.json` (applies only to this folder, CLI and extension), set `"claudeCode.disableLoginPrompt": true` in `.vscode/settings.json`, then run **Developer: Reload Window** and start a new chat. If the extension is signed in to a claude.ai account, it may keep using it: run `/logout` in the panel. Check with `/model` or `/status`: it should show `qwen3-coder-30b` and the base URL `http://localhost:8013`.

#### Hermes Agent

Install it (see the [quickstart](https://hermes-agent.nousresearch.com/docs/getting-started/quickstart)), then put this in `~/.hermes/config.yaml`:

```yaml
model:
  default: qwen3-coder-30b
  provider: custom
  base_url: http://localhost:8013/v1
  context_length: 65536
```

Or run `hermes model`, pick **Custom Endpoint**, and enter the same base URL, an empty API key and the model name. Keep `context_length` equal to `LLAMACPP_CONTEXT_LENGTH`.

### 9. Autocomplete (optional)

Neither agent does inline completion. To use the autocomplete server, install **llama.vscode** (`code --install-extension ggml-org.llama-vscode`) and set its completion endpoint to `http://localhost:8012`. Otherwise stop it: `docker stop llamacpp-autocomplete`.

## Usage

From the project folder:

- **Claude Code**: run `claude` in a terminal (with the variables from step 8), or open the Claude Code panel in VS Code. It reads and edits files and runs commands, asking before each action.
- **Hermes**: run `hermes` in a terminal.
- **Tab**: accept an autocomplete suggestion (llama.vscode).
