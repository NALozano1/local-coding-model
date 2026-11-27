# local-coding-model

Use the Inkling 2 Mini model on our GPU server (NVIDIA A30, 24 GB) as a coding assistant.

The **model** runs on the server. Your **coding agent** (Pi or opencode) runs on the server or on your
own computer. Everything is already installed on the server in `/home/shared/local-coding-model/`.

Replace `<server>`, `<jump-host>`, `<username>` and `<key>` with your own.

## 1. Start a model (on the server)

    /home/shared/local-coding-model/serve.sh maya-q4      # start (runs in the background)
    /home/shared/local-coding-model/serve.sh stop         # stop (only the person who started it can)

It returns when the model is ready and keeps running after you log out. One model runs at a time, so
check first with `curl http://127.0.0.1:8080/v1/models`, and stop it before starting another.

| Start with                    | Model name to use in your agent | Context | GPU memory | Tokens/s, 1 request | Tokens/s, 4 at once (total) |
|-------------------------------|---------------------------------|---------|------------|---------------------|-----------------------------|
| `serve.sh maya-q4`            | `inkling-2-mini-q4`             | 64k     | 18.5 GiB   | 95                  | 135                         |
| `serve.sh maya-q4 --drafter`  | `inkling-2-mini-q4`             | 64k     | 19.3 GiB   | 131                 | 133                         |
| `serve.sh maya-q8`            | `inkling-2-mini-q8`             | 64k     | 20.9 GiB   | 58                  | 69                          |
| `serve.sh maya-q8 --drafter`  | `inkling-2-mini-q8`             | 64k     | 21.8 GiB   | 73                  | 70                          |
| `serve.sh llama`              | `inkling-2-mini-q4`             | 16k     | 18.2 GiB   | 43 *                | not measured                |
| `serve.sh llama --drafter`    | `inkling-2-mini-q4`             | 16k     | 19.7 GiB   | 61 *                | not measured                |

Speeds are from single short runs. Maya: 12 Python tasks. \* llama.cpp: a few short agent tasks at 16k,
so do not compare it closely with Maya.

The drafter (speculative decoding) speeds up a single request, not the total for 4 at once.

## 2. Context size

Change it with `--ctx`, for example `serve.sh maya-q4 --ctx 131072`.

| Setup                | 32k        | 64k                | 128k               | 256k               |
|----------------------|------------|--------------------|--------------------|--------------------|
| `maya-q4`            | yes        | yes                | yes                | yes †              |
| `maya-q4 --drafter`  | yes        | yes                | yes                | yes †              |
| `maya-q8`            | yes        | yes                | about half speed ‡ | about half speed ‡ |
| `maya-q8 --drafter`  | yes        | yes                | not tested         | not tested         |
| `llama`              | not tested | no (out of memory) | no                 | no                 |
| `llama --drafter`    | not tested | no (out of memory) | no                 | no                 |

† A prompt of that length or longer was read and answered. Other "yes" cells started on the GPU, or are
smaller than a size that did.
‡ It starts, but part of the model moves to system memory. Maya reports 110592 as the most that stays on
the GPU. llama.cpp works at 16k.

## 3. Set up your agent

### The settings (same on the server and on your computer)

| Setting         | Value                                                             |
|-----------------|-------------------------------------------------------------------|
| Base URL        | `http://127.0.0.1:8080/v1`                                        |
| API type        | OpenAI-compatible (`openai-completions`)                          |
| API key         | none needed (put any text, e.g. `none`)                           |
| Model name      | `inkling-2-mini-q4` or `inkling-2-mini-q8`, as in the first table |
| Context window  | the server's `--ctx` (65536; llama.cpp 16384)                     |

Choosing a model in your agent does **not** change what the server runs. Match it to step 1.

### Pi

Put this in `~/.pi/agent/models.json` (Windows: `C:\Users\<you>\.pi\agent\models.json`). If the file
already has providers, add only the `"local-llm"` block inside `"providers"`.
Same file: [`pi/models.json`](pi/models.json).

```json
{
  "providers": {
    "local-llm": {
      "baseUrl": "http://127.0.0.1:8080/v1",
      "api": "openai-completions",
      "apiKey": "none",
      "models": [
        { "id": "inkling-2-mini-q4", "name": "Inkling 2 Mini Q4", "reasoning": true, "contextWindow": 65536, "maxTokens": 8192 },
        { "id": "inkling-2-mini-q8", "name": "Inkling 2 Mini Q8", "reasoning": true, "contextWindow": 65536, "maxTokens": 8192 }
      ]
    }
  }
}
```

Then run, in your project folder:

    pi --provider local-llm --model inkling-2-mini-q4

To make that the default so plain `pi` works, add the two entries in
[`pi/settings.json`](pi/settings.json) to `~/.pi/agent/settings.json`.

**With llama.cpp (16k):** set `contextWindow` to `16384`, and also add this to `settings.json`, because
Pi's default keeps the whole 16k free:

    "compaction": { "reserveTokens": 4096, "keepRecentTokens": 6000 }

**No Pi of your own on the server?** Run `/home/shared/local-coding-model/pi.sh` in your project folder.
It uses the shared install, and keeps your copy of the config in `~/.pi-local-coding-model/`.

To install Pi (needs [Node](https://nodejs.org) 22.19 or newer):

    npm install -g --ignore-scripts @earendil-works/pi-coding-agent

### opencode

Needs more than 16k of context (its first request was up to 18k tokens), so use a Maya model.

Copy [`opencode/opencode.json`](opencode/opencode.json) to `~/.config/opencode/opencode.json`
(Windows: `C:\Users\<you>\.config\opencode\`). If you already have that file, add the `"local-llm"`
block inside its `"provider"`. Run `opencode` and type `/models` to switch between Q4 and Q8.

Tested with opencode 1.2.6 and 1.19.6. Install with `npm install -g opencode-ai` (version 2 uses a
different config format).

## 4. From your own computer: open the tunnel

Skip this if your agent runs on the server.

**Once:** add this to `~/.ssh/config` (Windows: `C:\Users\<you>\.ssh\config`).
Without a jump host, leave out the first block and the `ProxyJump` line.

    Host llm-jump
      HostName <jump-host>
      User <username>
      IdentityFile ~/.ssh/<key>

    Host llm
      HostName <server>
      User <username>
      IdentityFile ~/.ssh/<key>
      ProxyJump llm-jump
      LocalForward 8080 127.0.0.1:8080
      ExitOnForwardFailure yes

**Every time:** run this and leave the terminal open. It prints nothing.

    ssh -N llm

In another terminal, `curl http://127.0.0.1:8080/v1/models` (`curl.exe` in PowerShell) should show the
model that is running.

## What the scripts run

| File here | What it does | What it calls |
|---|---|---|
| [`serve.sh`](serve.sh) with `maya-q4` / `maya-q8` | writes a config, starts Maya | [`serve/server.py`](https://github.com/alesha-pro/maya-inkling-mini/blob/27daec5e608aa59dab45184e82a1f0611ea7c1aa/serve/server.py), which runs the GPU engine built from [`src/`](https://github.com/alesha-pro/maya-inkling-mini/tree/27daec5e608aa59dab45184e82a1f0611ea7c1aa/src) |
| [`serve.sh`](serve.sh) with `llama` | starts llama.cpp | `llama-server`, built from [`tools/server`](https://github.com/ggml-org/llama.cpp/tree/0e4e925e8fa3d784b39f450050511576a0c8869b/tools/server) |
| [`pi.sh`](pi.sh) | runs Pi on the server | the shared Pi install |
| [`patches/maya-q8.patch`](patches/maya-q8.patch) | our changes to Maya for Q8, including the tool that converts the Q8 model file | applied to the Q8 build only |
| [`upstream/`](upstream/) | links to the exact Maya and llama.cpp versions used | |

## Good to know

- Everyone shares one server: 4 requests run at once and share the context.
- The server has no password and only listens on the server itself, hence the tunnel.
- It does not restart after a reboot. Logs are in `/home/shared/local-coding-model/logs/`.
- Both agents run commands and edit files, so start them in a project folder.
