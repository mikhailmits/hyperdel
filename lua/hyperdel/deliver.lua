local animation = require("hyperdel.animation")
local config = require("hyperdel.config")
local nvim = require("hyperdel.nvim")
local telegram = require("hyperdel.telegram")

local M = {}

local function view(bufnr, line1, line2)
	local win = vim.api.nvim_get_current_buf() == bufnr and vim.api.nvim_get_current_win() or vim.fn.bufwinid(bufnr)
	if win == -1 then
		return nil
	end
	vim.cmd("redraw")
	local info = vim.fn.getwininfo(win)[1]
	local leftcol = vim.api.nvim_win_call(win, vim.fn.winsaveview).leftcol
	return {
		win = win,
		topline = info.topline,
		textoff = info.textoff,
		leftcol = leftcol,
		winbar = info.winbar or 0,
		width = info.width - info.textoff,
		height = info.height,
		cells = nvim.cells(win, line1, line2),
	}
end

local function after(cfg, bufnr, line1, line2, tick, done)
	if cfg.after_delivery == "keep" or not vim.api.nvim_buf_is_valid(bufnr) then
		return done()
	end
	if nvim.changedtick(bufnr) ~= tick then
		nvim.warn("buffer changed during delivery, text kept")
		return done()
	end
	local shown = view(bufnr, line1, line2)
	nvim.clear(bufnr, line1, line2)
	local function finish(untouched)
		if cfg.after_delivery == "close" and untouched and vim.api.nvim_buf_is_valid(bufnr) then
			nvim.close(bufnr)
			return done("close", shown)
		end
		done("clear", shown)
	end
	if cfg.animation and shown then
		return animation.play(shown, bufnr, finish)
	end
	finish(true)
end

function M.deliver(opts)
	opts = opts or {}
	local cfg = config.get()
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
	local line1 = opts.line1 or 1
	local line2 = opts.line2 or vim.api.nvim_buf_line_count(bufnr)
	local targets = config.resolve_targets(opts.targets)
	if #targets == 0 then
		return nvim.warn("no targets configured")
	end
	local text = nvim.get_text(bufnr, line1, line2)
	if not text:match("%S") then
		return nvim.warn("nothing to deliver")
	end
	local tick = nvim.changedtick(bufnr)
	local delivered, errors = {}, {}

	local function report()
		for _, err in ipairs(errors) do
			nvim.error(err)
		end
		if #delivered == 0 then
			return
		end
		local names = vim.tbl_map(function(d)
			return d.name
		end, delivered)
		local sent = delivered[1].messages
		local summary =
			string.format("delivered to %s (%d message%s)", table.concat(names, ", "), sent, sent == 1 and "" or "s")
		if #errors > 0 then
			return nvim.warn(summary .. (cfg.after_delivery == "keep" and "" or ", text kept"))
		end
		nvim.brief(summary)
		after(cfg, bufnr, line1, line2, tick, function(done, shown)
			if cfg.on_delivered then
				cfg.on_delivered({
					targets = delivered,
					bufnr = bufnr,
					text = text,
					line1 = line1,
					cleared = done == "clear",
					closed = done == "close",
					view = shown,
				})
			end
		end)
	end

	local function deliver_to(i)
		local t = targets[i]
		if not t then
			return report()
		end
		telegram.deliver(t.chat, text, function(err, sent)
			if err then
				local partial = sent and sent > 0 and string.format(" after %d message(s)", sent) or ""
				table.insert(errors, "delivery to " .. t.name .. " failed" .. partial .. ": " .. err)
			else
				table.insert(delivered, { name = t.name, chat = t.chat, messages = sent })
			end
			deliver_to(i + 1)
		end)
	end

	telegram.ready(function(err)
		if err then
			return nvim.error("delivery failed: " .. err)
		end
		deliver_to(1)
	end)
end

return M
