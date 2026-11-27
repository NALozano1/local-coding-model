# local-coding-model

Inkling 2 Mini as a coding assistant. The model runs on a GPU server (NVIDIA A30, 24 GB). The agent
(Pi or opencode) runs there or on your own computer.

## 1. Start a model (on the server)

    cd /home/shared/local-coding-model
    ./serve.sh maya-q4      # runs in the background
    ./serve.sh stop         # only whoever started it can stop it

One model runs at a time. To see which: `curl http://127.0.0.1:8080/v1/models`

| `./serve.sh ...`    | Model name          | Context | GPU memory | tok/s, 1 request | tok/s total, 4 requests |
|---------------------|---------------------|---------|------------|------------------|-------------------------|
| `maya-q4`           | `inkling-2-mini-q4` | 64k     | 18.5 GiB   | 95               | 135                     |
| `maya-q4 --drafter` | `inkling-2-mini-q4` | 64k     | 19.3 GiB   | 131              | 133                     |
| `maya-q8`           | `inkling-2-mini-q8` | 64k     | 20.9 GiB   | 58               | 69                      |
| `maya-q8 --drafter` | `inkling-2-mini-q8` | 64k     | 21.8 GiB   | 73               | 70                      |
| `llama`             | `inkling-2-mini-q4` | 16k     | 18.2 GiB   | 43 *             | not measured            |
| `llama --drafter`   | `inkling-2-mini-q4` | 16k     | 19.7 GiB   | 61 *             | not measured            |

Single short runs. \* Measured on a different workload, so not directly comparable with Maya.

## 2. Context size

Set with `--ctx`, e.g. `./serve.sh maya-q4 --ctx 131072`.

| Setup               | 32k        | 64k           | 128k          | 256k          |
|---------------------|------------|---------------|---------------|---------------|
| `maya-q4` (± drafter) | yes      | yes           | yes           | yes           |
| `maya-q8`           | yes        | yes           | half speed †  | half speed †  |
| `maya-q8 --drafter` | yes        | yes           | not tested    | not tested    |
| `llama` (± drafter) | not tested | out of memory | no            | no            |

† Spills into system memory above 110592.

## 3. Connect from your computer

Skip this if the agent runs on the server.

Add to `~/.ssh/config`, filling in the `<...>` values (no jump host: drop `llm-jump` and `ProxyJump`):

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

Then keep this running while you work (it prints nothing):

    ssh -N llm

## 4. Set up your agent

Same settings on the server and on your computer:

| Setting        | Value                                      |
|----------------|--------------------------------------------|
| Base URL       | `http://127.0.0.1:8080/v1`                 |
| API            | OpenAI-compatible (`openai-completions`)   |
| API key        | any text                                   |
| Model          | `inkling-2-mini-q4` or `inkling-2-mini-q8` |
| Context window | same as the server (default 65536)         |

Pick the model the server is running; the agent's choice doesn't change it.

### Pi

Install (Node 22.19+):

    npm install -g --ignore-scripts @earendil-works/pi-coding-agent

Add to `~/.pi/agent/models.json` ([file](pi/models.json)):

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

Run in your project folder:

    pi --provider local-llm --model inkling-2-mini-q4

- **Default model:** copy the entries in [`pi/settings.json`](pi/settings.json) to `~/.pi/agent/settings.json`.
- **llama.cpp:** set `contextWindow` to `16384` and add to `settings.json`:
  `"compaction": { "reserveTokens": 4096, "keepRecentTokens": 6000 }`
- **On the server without your own Pi:** run `/home/shared/local-coding-model/pi.sh`
  (config in `~/.pi-local-coding-model/`).

### opencode

Needs a Maya model (16k is too small).

    npm install -g opencode-ai

Copy [`opencode/opencode.json`](opencode/opencode.json) to `~/.config/opencode/`, or add its
`local-llm` block to your existing config. Run `opencode`; switch models with `/models`.
Tested on 1.2.6 and 1.19.6 (version 2 uses a different format).

## Code

| File | Runs |
|---|---|
| [`serve.sh`](serve.sh) `maya-*` | Maya's [`server.py`](https://github.com/alesha-pro/maya-inkling-mini/blob/27daec5e608aa59dab45184e82a1f0611ea7c1aa/serve/server.py) and [engine](https://github.com/alesha-pro/maya-inkling-mini/tree/27daec5e608aa59dab45184e82a1f0611ea7c1aa/src) |
| [`serve.sh`](serve.sh) `llama` | llama.cpp's [`llama-server`](https://github.com/ggml-org/llama.cpp/tree/0e4e925e8fa3d784b39f450050511576a0c8869b/tools/server) |
| [`pi.sh`](pi.sh) | the shared Pi install |
| [`patches/maya-q8.patch`](patches/maya-q8.patch) | changes to Maya for Q8, including the model converter |
| [`upstream/`](upstream/) | exact Maya and llama.cpp versions |

## Notes

- 4 requests run at once and share the context.
- No password; the server only listens on `127.0.0.1`.
- No restart after reboot. Logs are in `logs/`.
- Agents run commands and edit files, so start them in a project folder.
