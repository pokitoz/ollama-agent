# Self-hosted LLM for coding in VS Code

Two backends are available:

- **llama.cpp** (default): `Dockerfile.llamacpp` + `docker-compose.llamacpp.yml`. One server for chat (port 8013), one for autocomplete (port 8012).
- **Ollama**: `Dockerfile` + `docker-compose.yml`. One server for both (port 11434). See [Using Ollama instead](#using-ollama-instead).

## 1. Configure the extension

Install **Continue** (`code --install-extension Continue.continue`), then put this in `C:\Users\florian.depraz\.continue\config.yaml`:

```yaml
name: Local llama.cpp
version: 1.0.0
schema: v1
models:
  - name: Qwen3 Coder 30B
    provider: openai
    model: qwen3-coder-30b
    apiBase: http://localhost:8013/v1
    apiKey: none
    capabilities: [tool_use]
    defaultCompletionOptions:
      contextLength: 32768
    roles: [chat, edit, apply]
  - name: Qwen2.5 Coder 1.5B
    provider: llama.cpp
    model: qwen2.5-coder-1.5b
    apiBase: http://localhost:8012/
    roles: [autocomplete]
```

Each llama.cpp server runs a single model, so `model` is only a label (keep `qwen2.5-coder` in the autocomplete one, Continue uses it to pick the autocomplete prompt format). `capabilities: [tool_use]` is required for agent mode: Continue doesn't recognize the label, so it won't send tools otherwise. Keep only these models: if Continue adds its default Ollama models (Llama 3.1, Nomic Embed...), remove them, they don't exist in this setup.

## 2. Get the model

In `.env`, set the Hugging Face GGUF models (`repo:quant`) to download on startup:

```
LLAMACPP_CHAT_MODEL=unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF:Q4_K_M
LLAMACPP_AUTOCOMPLETE_MODEL=ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF:Q8_0
```

Qwen3-Coder 30B-A3B is a mixture-of-experts model (~18 GB, 3B active per token) with native tool calling, needed for Continue's agent mode. It doesn't fit in 6 GB of VRAM, so `LLAMACPP_CHAT_N_CPU_MOE` keeps that many of its 48 expert layers in RAM (needs ~20 GB free RAM). Lower it for speed while VRAM allows, raise it if the model fails to load.

`bartowski/Qwen2.5-Coder-7B-Instruct-GGUF:Q4_K_M` is a smaller alternative that fits fully in VRAM, but it writes tool calls as text, so agent mode can't run them.

## 3. Set up the GPU (one time)

From PowerShell:

```powershell
wsl -d Ubuntu-22.04 --cd /mnt/c/Users/florian.depraz/ollama -- bash scripts/install-nvidia-toolkit.sh
```

When asked, enter your WSL Ubuntu password (nothing appears while you type). It's done when it prints a table showing your GPU.
If you forgot the password, reset it with `wsl -d Ubuntu-22.04 -u root passwd depraz`.

## 4. Start Docker

From PowerShell:

```powershell
# GPU
wsl -d Ubuntu-22.04 --cd /mnt/c/Users/florian.depraz/ollama -- docker compose -f docker-compose.llamacpp.yml up -d --build

# CPU only
wsl -d Ubuntu-22.04 --cd /mnt/c/Users/florian.depraz/ollama -- docker compose -f docker-compose.llamacpp.yml -f docker-compose.llamacpp.cpu.yml up -d --build
```

The first start downloads the models. Follow it with `wsl -d Ubuntu-22.04 -- docker logs -f llamacpp-chat` (and `llamacpp-autocomplete`).

To check the chat model runs on the GPU, look for `offloaded 49/49 layers to GPU` in the logs, or run `wsl -d Ubuntu-22.04 -- nvidia-smi` and look for a `llama-server` process. Autocomplete runs on the CPU (`--n-gpu-layers "0"`) to leave the VRAM to the chat model.

If generation is very slow (a few tokens/s), the VRAM is overflowing: raise `LLAMACPP_CHAT_N_CPU_MOE` in `.env`.

Optional chat UI on http://localhost:3000: add `--profile ui` to the `docker compose` command.

## 5. Prompt

In VS Code:

- **Ctrl+L**: chat (select code first to ask about it)
- **Agent** mode (dropdown under the chat input): let the model read, create and edit files and run commands
- **Ctrl+I**: edit the selected code from an instruction
- **Tab**: accept an autocomplete suggestion
