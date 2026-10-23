local config = require("hyperdel.config")
local nvim = require("hyperdel.nvim")
local telegram = require("hyperdel.telegram")

local M = {}

local function view(bufnr)
	local win = vim.api.nvim_get_current_buf() == bufnr and vim.api.nvim_get_current_win() or vim.fn.bufwinid(bufnr)
	if win == -1 then
		return nil
	end
	local info = vim.fn.getwininfo(win)[1]
	local leftcol = vim.api.nvim_win_call(win, vim.fn.winsaveview).leftcol
	return { win = win, topline = info.topline, textoff = info.textoff, leftcol = leftcol }
end

local function after(cfg, bufnr, line1, line2, tick)
	if cfg.after_delivery == "keep" or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	if nvim.changedtick(bufnr) ~= tick then
		return nvim.warn("buffer changed during delivery, text kept")
	end
	if cfg.after_delivery == "clear" then
		local shown = view(bufnr)
		nvim.clear(bufnr, line1, line2)
		return true, shown
	end
	nvim.close(bufnr)
end

function M.deliver(opts)
	opts = opts or {}
	local cfg = config.get()
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
	local line1 = opts.line1 or 1
	local line2 = opts.line2 or vim.api.nvim_buf_line_count(bufnr)
	local name, target = config.resolve_target(opts.target)
	local text = nvim.get_text(bufnr, line1, line2)
	if not text:match("%S") then
		return nvim.warn("nothing to deliver")
	end
	local tick = nvim.changedtick(bufnr)
	telegram.deliver(target, text, function(err, sent)
		if err then
			local partial = sent and sent > 0 and string.format(" after %d message(s)", sent) or ""
			return nvim.error("delivery to " .. name .. " failed" .. partial .. ": " .. err)
		end
		nvim.notify(string.format("delivered to %s (%d message%s)", name, sent, sent == 1 and "" or "s"))
		local cleared, shown = after(cfg, bufnr, line1, line2, tick)
		if cfg.on_delivered then
			cfg.on_delivered({
				target = name,
				chat = target,
				bufnr = bufnr,
				text = text,
				messages = sent,
				line1 = line1,
				cleared = cleared == true,
				view = shown,
			})
		end
	end)
end

return M
