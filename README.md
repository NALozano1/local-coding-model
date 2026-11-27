# local-coding-model

Run [Inkling 2 Mini](https://huggingface.co/thinkingmachines/Inkling-2-Mini) on one 24 GB NVIDIA GPU with
llama.cpp or [Maya](https://github.com/alesha-pro/maya-inkling-mini), and use it from the
[Pi](https://pi.dev) coding agent. Tested on an NVIDIA A30 (Linux), with Pi on Windows.

First time? Follow [docs/setup.md](docs/setup.md) to build the engines and get the models.

## 1. Start the model (on the GPU server)

    tmux new -s llm
    ./serve.sh maya-q4

Press `Ctrl+b` then `d` to leave it running.

## 2. Use it: pick A or B

### A. On the server

    cd your-project
    /path/to/local-coding-model/pi.sh

Needs [Node](https://nodejs.org) 22.19 or newer and Pi
(`npm install -g --ignore-scripts @earendil-works/pi-coding-agent`).

### B. From your own computer

**Once:** install Node 22.19 or newer and Pi, then copy the two files in [`pi/`](pi/) to `~/.pi/agent/`
(Windows: `%USERPROFILE%\.pi\agent\`). This replaces any files of the same name you already have.

**Every time:** open an SSH tunnel and leave it open (it prints nothing):

    ssh -N -L 8080:127.0.0.1:8080 <user>@<server>

Behind a jump host, add `-J <user>@<jump-host>`. Then, in a second terminal:

    cd your-project
    pi

Pi runs commands and edits files without asking, so start it in a project folder.

## Change the model

Stop the running server (`tmux send-keys -t llm C-c`), then start another one:

| Command                      | Model                          |
|------------------------------|--------------------------------|
| `./serve.sh maya-q4`         | Maya, Q4                       |
| `./serve.sh maya-q8`         | Maya, Q8                       |
| `./serve.sh llama`           | llama.cpp, Q4                  |
| add `--drafter`              | drafter on (default: off)      |
| add `--ctx 32768`            | bigger context (default 16384) |

- In Pi, `/model` should match what the server runs (q4 or q8). It only changes the label.
- After raising `--ctx`, raise `contextWindow` in Pi's `models.json` to the same number.

## Good to know

- 4 requests run at once and share the context. There is no password: it listens on `127.0.0.1` only.
- The server does not restart after a reboot.
- Logs are written to `logs/`.
