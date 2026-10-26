# hyperdel

Deliver your thoughts to anywhere (currently only to Telegram) from Neovim.


## Usage

## Requirements

- Neovim 0.8+
- `curl`, `tar` and one of `shasum`, `sha512sum`, `openssl` or `certutil` for the TDLib download
- `api_id` and `api_hash` keys from https://my.telegram.org

## Install

### lazy.nvim

```lua
{
  "mikhailmits/hyperdel",
  opts = {
    api_id = 12345,
    api_hash = "your_api_hash",
  },
}
```
Run :HyperdelSetup, once you've installed the plugin.


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
vim.pack.add({ "https://github.com/mikhailmits/hyperdel" })
require("hyperdel").setup({ api_id = 12345, api_hash = "your_api_hash" })
```
Run :HyperdelSetup, once you've installed the plugin.


### Manually or with your own TDLib

Run `:HyperdelSetup`.
`:HyperdelSetup!` reinstalls the plugin and relogins to your telegram account, logs you out and logs you in again.

To use a TDLib you built yourself, set `tdjson_path` to the full path of `libtdjson`.

Check everything: `:checkhealth hyperdel`.

## Usage examples

| Command| Meaning |
|---|---|
| `:hy saved` | Publish the whole nvim buffer to your Saved Messages |
| `:hy saved ideas -1001234567890` | Deliver to several targets (targets may be set in options |
| `:hy` or `<leader>hy` | Publish everywhere you've set |
| `:'<,'>hy [targets]` | Publish the selected lines |
| `:HyperdelSetup` | Finish plugin installation and log in |
| `:HyperdelSetup!` | Reinstall the plugin, log out and log in again |
| `:HyperdelLogout` | Log out and end the Telegram session |

`:hy` is shorthand for `:Hy`, which works too.

Login asks for your phone number and the code Telegram sends you, additionally may ask for 2FA code if set. The session is stored in `stdpath("data")/hyperdel/tdlib`, so you log in once.

Long notes are split into several messages at line boundaries. 

## Configuration

```lua
require("hyperdel").setup({
  api_id = nil,
  api_hash = nil,
  targets = {
    saved = "saved",
    ideas = "@my_ideas_channel",
    private = -1001234567890,
  },
  after_delivery = "keep",
  on_delivered = nil,
  keymap = "<leader>hy",
  tdjson_path = nil,
  data_dir = vim.fn.stdpath("data") .. "/hyperdel",
  log_level = 1,
})
```

- `api_id`, `api_hash`: can also come from `HYPERDEL_API_ID` and `HYPERDEL_API_HASH`.
- `targets`: names you can pass to `:hy`, and the list that `:hy` without arguments and the keymap deliver to. A value is `"saved"` (your Saved Messages), a public `"@username"`, or a numeric chat id. A raw `@username` or chat id also works as a command argument. Your table replaces the default `{ saved = "saved" }`, so add `saved` if you still want it.
- `after_delivery`: `"keep"` leaves the text, `"clear"` removes the delivered lines, `"close"` deletes the buffer. Nothing happens if the buffer was edited while delivering.
- `on_delivered`: `function(info)` called once after every target succeeded, with `{ targets, bufnr, text, line1, cleared, closed, view }`. `targets` lists each delivery as `{ name, chat, messages }`. `cleared` is true when `after_delivery = "clear"` removed the text, `closed` is true when `after_delivery = "close"` deleted the buffer, and `view` holds the window it was shown in (`win`, `topline`, `textoff`, `leftcol`, `winbar`, `width`, `height`) and `cells`, the delivered text exactly as it was drawn on screen, one `{ row, col, ch, w }` per character, relative to the text area. Use it for custom actions such as closing a terminal tab.
- `require("hyperdel.animation").collapse`: a ready-made `on_delivered` for `after_delivery = "clear"`. The delivered letters gather in the middle of the window and fall to the bottom, where they disappear.
- `require("hyperdel.animation").collapse_quit`: a ready-made `on_delivered` for `after_delivery = "close"`. It plays the same animation, then quits Neovim with `:confirm qall`, so other unsaved buffers are asked about instead of lost.
- `keymap`: a key for normal mode (whole buffer) and visual mode (selection) that delivers to all targets. Set it to `false` to map nothing.
- `log_level`: TDLib log verbosity. Logs go to `data_dir/tdlib.log`, never to the screen.

