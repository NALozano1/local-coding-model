# local-coding-model

Inkling 2 Mini on the GPU server, used from a coding agent. Everything is already installed on the
server in `/home/shared/local-coding-model/`.

Replace `<server>`, `<jump-host>`, `<username>` and `<key>` with your own.

## 1. Start the model (on the server)

Skip this if `curl http://127.0.0.1:8080/v1/models` on the server already answers.

    tmux new -s llm
    /home/shared/local-coding-model/serve.sh maya-q4

Press `Ctrl+b` then `d` to leave it running.

| Command (after the path above) | Model                          |
|--------------------------------|--------------------------------|
| `serve.sh maya-q4`             | Maya, Q4                       |
| `serve.sh maya-q8`             | Maya, Q8                       |
| `serve.sh llama`               | llama.cpp, Q4                  |
| add `--drafter`                | drafter on (default: off)      |
| add `--ctx 32768`              | bigger context (default 16384) |

To switch, stop the running one first (only the person who started it can):

    tmux send-keys -t llm C-c

## 2. Use Pi on the server

    cd your-project
    /home/shared/local-coding-model/pi.sh

## 3. Use Pi or opencode on your own computer

### Set up the tunnel (once)

Add to `~/.ssh/config` (Windows: `C:\Users\<you>\.ssh\config`). Without a jump host, leave out the
first block and the `ProxyJump` line.

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

### Open the tunnel (every time)

In its own terminal, left open. It prints nothing.

    ssh -N llm

Or run it in the background:

| System         | Open                                                          | Close                                                                              |
|----------------|---------------------------------------------------------------|------------------------------------------------------------------------------------|
| Windows        | `Start-Process ssh -ArgumentList '-N','llm' -WindowStyle Hidden` | `Stop-Process -Id (Get-NetTCPConnection -LocalPort 8080 -State Listen).OwningProcess` |
| macOS or Linux | `ssh -f -N llm`                                               | `pkill -f "ssh -f -N llm"`                                                          |

The background form needs a key that does not ask for a passphrase (or one loaded in `ssh-agent`).

Check it (`curl.exe` in PowerShell):

    curl http://127.0.0.1:8080/v1/models

### Pi

Needs [Node](https://nodejs.org) 22.19 or newer. Once, replacing any files of the same name:

Windows (PowerShell):

    npm install -g --ignore-scripts @earendil-works/pi-coding-agent
    mkdir -Force $HOME\.pi\agent
    scp "llm:/home/shared/local-coding-model/pi/*.json" $HOME\.pi\agent\

macOS or Linux:

    npm install -g --ignore-scripts @earendil-works/pi-coding-agent
    mkdir -p ~/.pi/agent
    scp "llm:/home/shared/local-coding-model/pi/*.json" ~/.pi/agent/

Then run `pi` in your project folder.

### opencode

This config is for [opencode](https://opencode.ai) 1.x; version 2 uses a different format.
Once (if you already have an `opencode.json`, copy the `local-llm` block into it instead):

Windows (PowerShell):

    npm install -g opencode-ai
    mkdir -Force $HOME\.config\opencode
    scp llm:/home/shared/local-coding-model/opencode/opencode.json $HOME\.config\opencode\

macOS or Linux:

    npm install -g opencode-ai
    mkdir -p ~/.config/opencode
    scp llm:/home/shared/local-coding-model/opencode/opencode.json ~/.config/opencode/

Then run `opencode` in your project folder.

## Good to know

- Both agents run commands and edit files on the machine they run on. Start them in a project folder.
- In the agent, pick the model (q4 or q8) the server is running. It only changes the label.
- After raising `--ctx`, raise the context number in the agent's config to match
  (`contextWindow` for Pi, `limit.context` for opencode).
- 4 requests run at once and share the context. The server has no password and only listens on the
  server itself, hence the tunnel. It does not restart after a reboot.

## Files

Copies of the config files: [`pi/`](pi/) and [`opencode/`](opencode/).
