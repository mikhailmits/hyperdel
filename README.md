# hyperdel

https://github.com/user-attachments/assets/cd06bcfe-0c46-4e6f-95d9-fda7eda8b216
Deliver your thoughts to anywhere (currently only to Telegram) from Neovim.

## Quick Usage Guide
In nvim command-line run `:HyperdelSetup` if you've just installed the plugin.
To log in with a QR code instead, type `qr` when it asks for your phone number or login code.

In order to publish your neovim selection/whole window to Saved messages run the next in nvim command-line mode: `hy saved`.
Or just press `<leader>hy`.

You may configure the `hy <target>` targets in order to specify where to publish your nvim buffer, see the Configuration section below.

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
    api_id = "replace me",
    api_hash = "replace me",
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
`:HyperdelSetup!` reinstalls the plugin, logs you out, deletes the saved Telegram session and phone number, and logs you in again.

To use a TDLib you built yourself, set `tdjson_path` to the full path of `libtdjson`.

Check everything: `:checkhealth hyperdel`.

## Configuration

```lua
require("hyperdel").setup({
  api_id = nil,   -- from https://my.telegram.org, or env HYPERDEL_API_ID
  api_hash = nil, -- from https://my.telegram.org, or env HYPERDEL_API_HASH

  -- where to publish; :hy or <leader>hy with no target publishes to all of them
  -- your list replaces the default, which is only saved
  targets = {
    saved = "saved",             -- your Saved Messages
    ideas = "@my_ideas_channel", -- a public channel or user
    private = -1001234567890,    -- any chat, by id
  },

  -- "keep" the text, "clear" it, or "close" nvim (and its tab when running in Rex)
  after_delivery = "keep",
  animation = true, -- on "clear" and "close" the letters fall away first
  on_delivered = nil, -- function(info) to run after publishing and the animation

  keymap = "<leader>hy", -- publishes buffer or selection to all targets; false = no key
  tdjson_path = nil,     -- path to your own libtdjson build
  data_dir = vim.fn.stdpath("data") .. "/hyperdel", -- login session and logs
  log_level = 1,         -- TDLib log detail, saved to data_dir/tdlib.log
})
```

