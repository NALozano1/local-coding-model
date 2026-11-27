# local-coding-model

Use the Inkling 2 Mini model on our GPU server as a coding assistant.

The **model** runs on the server. Your **coding agent** (Pi or opencode) runs on your own computer
and reaches the model through an SSH tunnel.

Replace `<server>`, `<jump-host>`, `<username>` and `<key>` with your own.

## 1. Start a model (on the server)

First check whether one is already running: `curl http://127.0.0.1:8080/v1/models`.
If it answers, go to step 2.

    tmux new -s llm
    /home/shared/local-coding-model/serve.sh maya-q4

Press `Ctrl+b` then `d` to leave it running. Pick one **deployment**:

| Command            | Engine and precision | In your agent, choose | GPU memory (with drafter) |
|--------------------|----------------------|-----------------------|---------------------------|
| `serve.sh maya-q4` | Maya, Q4             | `inkling-2-mini-q4`   | 18.1 GB (19.0 GB)         |
| `serve.sh maya-q8` | Maya, Q8             | `inkling-2-mini-q8`   | 19.8 GB (20.7 GB)         |
| `serve.sh llama`   | llama.cpp, Q4        | `inkling-2-mini-q4`   | 18.7 GB (20.1 GB)         |

Options, added after the command:

- `--drafter` turns on speculative decoding (off by default).
- `--ctx 32768` sets the context size (16384 by default). Memory figures above are for the default.

To switch deployment, stop the running one first (only the person who started it can):

    tmux send-keys -t llm C-c

## 2. Open the tunnel (on your computer)

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

In another terminal, `curl http://127.0.0.1:8080/v1/models` (`curl.exe` in PowerShell) should show
the model that is running.

## 3. Add the model to your agent (on your computer)

Your agent only knows about this server once you add its config. You do this **once**: it covers every
deployment, because they all use the same address. Afterwards just choose the matching model name.

### Pi

Install (needs [Node](https://nodejs.org) 22.19 or newer):

    npm install -g --ignore-scripts @earendil-works/pi-coding-agent

| Copy this file                          | To (Windows: `C:\Users\<you>\.pi\agent\`) | What it does                      |
|-----------------------------------------|-------------------------------------------|-----------------------------------|
| [`pi/models.json`](pi/models.json)      | `~/.pi/agent/models.json`                 | Adds the server and both models   |
| [`pi/settings.json`](pi/settings.json)  | `~/.pi/agent/settings.json`               | Makes Q4 the default; see below   |

- **No such file yet:** save the copy under that name.
- **You already have `models.json`:** add only the `"local-llm": { ... }` block inside your `"providers"`.
- **You already have `settings.json`:** add the three entries to yours. Keep the `compaction` one: Pi's
  default reserves 16384 tokens, which is the whole default context.

Run `pi` in your project folder. Type `/model` to choose Q4 or Q8.

### opencode

Install (version 1.x; version 2 uses a different config format):

    npm install -g opencode-ai

Copy [`opencode/opencode.json`](opencode/opencode.json) to `~/.config/opencode/opencode.json`
(Windows: `C:\Users\<you>\.config\opencode\`). If you already have that file, add the
`"local-llm": { ... }` block inside your `"provider"`.

Run `opencode` in your project folder. Type `/models` to choose Q4 or Q8.

## Pi on the server instead

No tunnel or config needed:

    cd your-project
    /home/shared/local-coding-model/pi.sh

## Good to know

- Choosing a model in the agent does **not** change what the server runs. Match it to step 1.
- If you raise `--ctx`, raise `contextWindow` (Pi) or `limit.context` (opencode) to the same number.
- Everyone shares one server: 4 requests run at once and share the context.
- The server does not restart after a reboot.
- Both agents run commands and edit files, so start them in a project folder.
