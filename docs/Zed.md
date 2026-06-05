# Zed Development Notes

## Prerequisites

- Rust via rustup (`~/.cargo/env` must be sourced if cargo isn't on PATH)
- `cmake` (install via `brew install cmake`)
- The repo's `rust-toolchain.toml` pins Rust 1.93; rustup handles this automatically

## Building & Running

```bash
source ~/.cargo/env

# Debug build + run
cargo build --package zed
./target/debug/zed

# Or build and run in one step
cargo run --package zed

# Release build (optimized)
cargo run --package zed --release
```

## Nix

The repo includes `flake.nix`, `shell.nix`, and a `nix/` directory for a nix-based dev environment, but it's not required — standard rustup/cargo works fine on macOS.

## Projects / Workspaces

Zed doesn't have a project file format. Opening a folder *is* your project:

- `zed /path/to/folder` or drag a folder into Zed
- That folder becomes the "worktree" — the root for file search, tasks, LSP, etc.
- Per-project settings go in `.zed/settings.json` inside the project root
- Per-project tasks go in `.zed/tasks.json`
- `Cmd+P` to jump between files, `Cmd+Shift+P` for the command palette
- Zed spawns a login shell in the project directory for environment variables,
  so tools like `direnv`/`asdf`/`mise` work automatically

### Multi-Worktree (Multi-Root) Support

Zed supports multiple worktrees in a single window. Each worktree gets its own
LSP server instance rooted at that directory. This is critical for Metals/Scala
since Metals needs `build.sbt` at the workspace root.

**Adding worktrees:**
- CLI: `zed -a ~/WH/some-project` (adds to focused window)
- Command palette: `workspace: add folder to project`
- At launch: `zed ~/WH/project-a ~/WH/project-b` (opens all as worktrees)

**Note:** Zed does NOT yet implement LSP workspace folders
(`didChangeWorkspaceFolders`). Instead, it starts a separate Metals instance
per worktree. This works fine — each project gets its own Metals with the
correct root.

### CLI Shim vs App Binary (building from source)

When building Zed from source, there are two binaries:

| Binary | Crate | Purpose |
|--------|-------|---------|
| `target/release/zed` | `crates/zed` | The app itself. Simple arg parser, no `-a`/`-n`/`--wait`. |
| `target/release/cli` | `crates/cli` | CLI shim. Connects to running Zed via socket. Has `-a`, `-n`, `--wait`, etc. |

The CLI shim expects to find itself inside a `.app` bundle. When running from
`target/release/`, use `--zed` to point it at the app binary:

```bash
target/release/cli --zed target/release/zed -a /path/to/project
```

**Wrapper script** (`~/.local/bin/zed`):

```bash
#!/bin/sh
exec ~/workspace/zed/target/release/cli --zed ~/workspace/zed/target/release/zed "$@"
```

Build both:
```bash
cd ~/workspace/zed
cargo build --release -p zed -p cli
```

Launch Zed app directly (first time / from Dock), then use the wrapper for
all subsequent CLI interactions (`-a`, `--wait`, etc.).

## Nix Flake + Direnv Integration (Metals/Scala)

Projects with a `flake.nix` (e.g. internal repos needing custom CA certs for
Nexus) require the nix develop shell environment for sbt/Metals to resolve
dependencies. Zed handles this automatically via direnv:

### How it works

1. Zed spawns a login shell in the project directory when opening a worktree
2. If direnv is hooked into zsh and a `.envrc` exists, the nix environment
   activates (via nix-direnv's cached `use flake`)
3. That environment (JAVA_HOME, SBT_OPTS, PATH with nix JDK/sbt) is passed
   to Metals when Zed starts the LSP

### Setup (already done via home-manager)

```nix
# home-common.nix
programs.direnv = {
  enable = true;
  enableBashIntegration = true;
  nix-direnv.enable = true;
};
programs.zsh.enable = true;  # auto-enables direnv zsh hook
```

### Per-project: add `.envrc`

For any Scala project with a `flake.nix`:

```bash
echo 'use flake' > .envrc
direnv allow
```

Then add the worktree to Zed (`zed -a /path/to/project`). Metals will
inherit `SBT_OPTS` (with the custom truststore) and `JAVA_HOME` from the
flake's devShell.

### Troubleshooting

- **SSL cert errors in metals.log**: `.envrc` missing or not allowed
- **Wrong JDK**: check `direnv exec . env | grep JAVA_HOME`
- **Cache stale**: run `nix-direnv-reload` in the project directory
- **Metals logs**: `~/<project>/.metals/metals.log`
- **Zed LSP logs**: Cmd+Shift+P → `debug: open language server logs` → Metals

## Helix Mode

Zed has built-in Helix emulation. Enabled via `"helix_mode": true` in settings.
This automatically enables `vim_mode` underneath. Provides selection-first editing,
Helix-style surround, paste, yank, text objects, and `]`/`[` navigation.

Still a work in progress — tracking: https://github.com/zed-industries/zed/discussions/33580

Custom keybindings go in `keymap.json` (open via `zed: open keymap file` command).

## Kiro CLI Integration

Kiro CLI implements the Agent Client Protocol (ACP), which Zed supports natively.

### Configuration

Added to `~/.config/zed/settings.local.json` (machine-specific, not tracked in dotfiles):

```json
{
  "agent_servers": {
    "Kiro Agent": {
      "type": "custom",
      "command": "/Users/bbarker/.local/bin/kiro-cli",
      "args": ["acp"],
      "env": {}
    }
  }
}
```

### Usage

- Open the agent panel, click `+`, and select "Kiro Agent"
- Gets full Zed UI integration: inline diffs, @-mentions, streaming responses
- Alternatively, run `kiro-cli chat` in Zed's integrated terminal for the CLI experience

### Debugging

- `dev: open acp logs` in Zed's command palette to see JSON-RPC messages
- Kiro logs: `$TMPDIR/kiro-log/kiro-chat.log`

## Zed vs Other Editors

### Similarities

**Emacs**
- Command palette (`Cmd+Shift+P`) is similar in spirit to `M-x`
- Deep configurability via settings/keymaps (JSON instead of Lisp)
- Async, non-blocking background work

**Vi/Vim**
- First-class vim mode — modal editing, motions, text objects, visual mode
- `:` commands available in vim mode

**VS Code**
- Identical shortcuts: `Cmd+P` for files, `Cmd+Shift+P` for commands
- LSP integration, inline diagnostics, extensions
- Per-project settings (`.zed/settings.json` vs `.vscode/settings.json`)
- Integrated terminal and task runner (`.zed/tasks.json`)

**Helix**
- Built-in Helix emulation mode (`"helix_mode": true`) — see above
- Selection-first editing model, Helix-style surround/yank/paste, `]`/`[` navigation
- Both are fast, native-feeling editors with strong LSP integration out of the box
- Both use a "no config needed to be productive" philosophy compared to Vim/Emacs

**Acme (Plan 9)**
- Both treat the editor as a programmable surface
- Tasks/commands can pipe output back into the editor, echoing Acme's shell integration
- Spatial, multi-pane layout with mouse support

### What's Different from All of Them

- **Multiplayer / collaboration** — real-time co-editing is first-class, not a plugin. None of the others have this natively.
- **AI deeply integrated** — agent panel, inline assists, and ACP (e.g. Kiro) are core UI, not extensions. Helix has none of this; VS Code bolts it on.
- **No project file format** — the folder is the project. No `.code-workspace`, no session files, no Emacs desktop files. Multi-worktree via `zed -a` or `workspace: add folder to project`.
- **Single binary, GPU-rendered, no Electron** — near-instant startup. Full GUI with pixel-level rendering, unlike terminal-based Helix.
- **Extensions in WebAssembly** — sandboxed and fast, but ecosystem is smaller than VS Code's. Very different from Emacs Lisp packages or Vim plugins.
- **Helix mode is still a work in progress** — expect some gaps if coming from real Helix. See tracking link above.

## Acme-like Shell Integration

### Tasks (`.zed/tasks.json`)

The closest thing to Acme's "run a command in context." Tasks run shell commands with editor context variables:

- `$ZED_FILE` — current file path
- `$ZED_SELECTED_TEXT` — currently selected text
- `$ZED_WORKTREE_ROOT` — project root
- `$ZED_ROW`, `$ZED_COLUMN` — cursor position

Run via `Cmd+Shift+P` → "task: spawn", or bind to a key in `keymap.json`.

Example:
```json
[
  {
    "label": "Run file",
    "command": "python3 $ZED_FILE",
    "use_new_terminal": false,
    "reveal": "always"
  }
]
```

Full docs: https://zed.dev/docs/tasks

### Terminal Panel

`Ctrl+`` ` opens an integrated terminal at the project root — the most Acme-like workflow for running arbitrary commands alongside editor panes.

### Pipe Selection Through Shell

Acme's middle-click-to-pipe and Helix's `|` (pipe selection through command) / `!` (insert command output) don't have a direct equivalent in Zed's native UI.

**Vim mode workaround:** `:'<,'>!<command>` pipes selected lines through a shell command and replaces them in-buffer — same as Vim.

**Helix mode:** `|` and `!` may or may not be implemented — Helix emulation is a work in progress. Test by making a selection and pressing `|`. Check the tracking discussion for current status: https://github.com/zed-industries/zed/discussions/33580

## Config Sync via Dotfiles (home-manager)

Zed config lives in `~/.config/zed/`. The dotfiles repo at `~/workspace/dotfiles/` already uses
home-manager with per-machine nix files — the same pattern used for Helix config.

### File layout

```
dotfiles/.config/zed/settings.json     # shared base (tracked)
~/.config/zed/settings.local.json      # machine-specific overrides (gitignored)
```

`settings.local.json` holds anything machine-specific or sensitive (e.g. `agent_servers` for Kiro). It is never synced to the repo.

### Deploying (build.sh)

`build.sh` copies the base `settings.json` then merges `settings.local.json` on top using `jq` if it exists. Running build will never clobber local overrides.

### Syncing config into dotfiles

```sh
cd ~/workspace/dotfiles
./sync/zed.sh
```

Recursively copies `~/.config/zed/` into `dotfiles/.config/zed/`, stripping `agent_servers` from `settings.json` and excluding `settings.local.json` and `development_credentials`. Requires `jq` and `rsync`.

### home-manager wiring

In `home-common.nix`, link the shared files:

```nix
home.file.".config/zed/keymap.json".source = ../.config/zed/keymap.json;
home.file.".config/zed/settings.json".source = ../.config/zed/settings.base.json;
```

On machines with Kiro, merge the `agent_servers` block at activation time using `jq`:

```nix
home.file.".config/zed/settings.json" = {
  source = pkgs.runCommand "zed-settings" { buildInputs = [ pkgs.jq ]; } ''
    jq -s '.[0] * .[1]' \
      ${../.config/zed/settings.base.json} \
      ${builtins.toFile "kiro.json" (builtins.toJSON {
        agent_servers.Kiro\ Agent = {
          type = "custom";
          command = "/Users/bbarker/.local/bin/kiro-cli";
          args = [ "acp" ];
          env = {};
        };
      })} > $out
  '';
};
```

### API keys / secrets

Don't commit API keys to the repo. Options:
- Use [agenix](https://github.com/ryantm/agenix) or [sops-nix](https://github.com/Mic92/sops-nix) to decrypt secrets at activation time and write them into the merged settings file
- Or keep a gitignored `settings.secrets.json` on each machine and include it in the `jq` merge
