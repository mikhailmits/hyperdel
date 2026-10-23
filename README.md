# hyperdel

Deliver your thoughts anywhere. Write in any Neovim buffer, run `:Hyperdel`, and the text lands in your Telegram Saved Messages or a channel.

hyperdel talks to Telegram through [TDLib](https://core.telegram.org/tdlib) using its JSON interface (`libtdjson`) via LuaJIT FFI. No Node, Python or other runtime is needed.

## Requirements

- Neovim 0.8+
- `curl`, `tar` and one of `shasum`, `sha512sum`, `openssl` or `certutil` for the TDLib download
- An `api_id` and `api_hash` from https://my.telegram.org

## Install

The TDLib library (pinned to 1.8.69) is downloaded from the [`prebuilt-tdlib`](https://github.com/eilvelia/tdl/tree/main/packages/prebuilt-tdlib) npm packages, checked against a pinned SHA-512, and stored in `stdpath("data")/hyperdel/lib`.

### lazy.nvim

lazy.nvim runs `build.lua` on install and update, which downloads TDLib.

```lua
{
  "you/hyperdel",
  cmd = { "Hyperdel", "HyperdelLogin", "HyperdelLogout", "HyperdelInstall" },
  keys = { { "<leader>hd", mode = { "n", "x" } } },
  opts = {
    api_id = 12345,
    api_hash = "your_api_hash",
    keymap = "<leader>hd",
  },
}
```

### vim.pack (Neovim 0.12+)

```lua
vim.api.nvim_create_autocmd("PackChanged", {
  callback = function(ev)
    if ev.data.spec.name == "hyperdel" and ev.data.kind ~= "delete" then
      vim.cmd.packadd("hyperdel")
      require("hyperdel").install()
    end
  end,
})
vim.pack.add({ "https://github.com/you/hyperdel" })
require("hyperdel").setup({ api_id = 12345, api_hash = "your_api_hash" })
```

### Manually or with your own TDLib

Run `:HyperdelInstall` at any time (`:HyperdelInstall!` reinstalls). To use a TDLib you built yourself, set `tdjson_path` to the full path of `libtdjson`.

Check everything with `:checkhealth hyperdel`.

## Usage

| Command | What it does |
|---|---|
| `:Hyperdel [target]` | Deliver the whole buffer to `target` (default target if omitted) |
| `:'<,'>Hyperdel [target]` | Deliver the selected lines |
| `:HyperdelLogin` | Log in (also happens automatically on the first delivery) |
| `:HyperdelLogout` | Log out and end the Telegram session |
| `:HyperdelInstall[!]` | Download the prebuilt TDLib |

Login asks for your phone number, the code Telegram sends you and, if set, your two-step verification password. The session is stored in `stdpath("data")/hyperdel/tdlib`, so you log in once.

Long notes are split into several messages at line boundaries. Delivery is reported only after Telegram confirms every message.

## Configuration

```lua
require("hyperdel").setup({
  api_id = nil,
  api_hash = nil,
  default_target = "saved",
  targets = {
    saved = "saved",
    ideas = "@my_ideas_channel",
    private = -1001234567890,
  },
  after_delivery = "keep",
  on_delivered = nil,
  keymap = nil,
  tdjson_path = nil,
  data_dir = vim.fn.stdpath("data") .. "/hyperdel",
  log_level = 1,
})
```

- `api_id`, `api_hash`: can also come from `HYPERDEL_API_ID` and `HYPERDEL_API_HASH`.
- `targets`: names you can pass to `:Hyperdel`. A value is `"saved"` (your Saved Messages), a public `"@username"`, or a numeric chat id. A raw `@username` or chat id also works as the command argument.
- `after_delivery`: `"keep"` leaves the text, `"clear"` removes the delivered lines, `"close"` deletes the buffer. Nothing happens if the buffer was edited while delivering.
- `on_delivered`: `function(info)` called after a successful delivery with `{ target, chat, bufnr, text, messages, line1, cleared, view }`. `cleared` is true when `after_delivery = "clear"` removed the text, and `view` holds the window it was shown in (`win`, `topline`, `textoff`, `leftcol`). Use it for custom actions such as closing a terminal tab.
- `require("hyperdel.animation").collapse`: a ready-made `on_delivered` for `after_delivery = "clear"`. The delivered letters gather in the middle of the window and fall to the bottom, where they disappear.
- `keymap`: a key for normal mode (whole buffer) and visual mode (selection). No key is mapped by default.
- `log_level`: TDLib log verbosity. Logs go to `data_dir/tdlib.log`, never to the screen.

## Architecture

```
tdlib <- tdlib lua client <- nvim utils <- plugin functions <- plugin setup
```

| Layer | Files |
|---|---|
| tdlib lua client | `lua/hyperdel/tdlib/library.lua` (finds and loads `libtdjson`), `lua/hyperdel/tdlib/client.lua` (send/receive loop, `@extra` callbacks, update handlers) |
| nvim utils | `lua/hyperdel/nvim.lua` (buffer text, prompts, notifications, message splitting) |
| plugin functions | `lua/hyperdel/telegram.lua` (login, chat resolution, sending), `lua/hyperdel/deliver.lua` (buffer to target), `lua/hyperdel/install.lua` |
| plugin setup | `lua/hyperdel/init.lua`, `lua/hyperdel/config.lua`, `plugin/hyperdel.lua`, `build.lua`, `lua/hyperdel/health.lua` |

The TDLib client starts only on the first command, so it adds nothing to startup time. It polls `td_receive` every 50 ms on the main loop and closes TDLib cleanly on exit.
