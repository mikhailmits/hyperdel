local M = {}

function M.notify(msg, level)
	vim.notify("hyperdel: " .. msg, level or vim.log.levels.INFO)
end

function M.warn(msg)
	M.notify(msg, vim.log.levels.WARN)
end

function M.error(msg)
	M.notify(msg, vim.log.levels.ERROR)
end

function M.brief(msg)
	msg = "hyperdel: " .. msg
	local tail = "…"
	local room = vim.v.echospace
	if vim.fn.strdisplaywidth(msg) > room then
		room = room - vim.fn.strdisplaywidth(tail)
		if room < 1 then
			return
		end
		local n = vim.fn.strchars(msg)
		while n > 0 and vim.fn.strdisplaywidth(vim.fn.strcharpart(msg, 0, n)) > room do
			n = n - 1
		end
		msg = vim.fn.strcharpart(msg, 0, n) .. tail
	end
	vim.notify(msg, vim.log.levels.INFO)
end

function M.expand_hy()
	if vim.fn.getcmdtype() == ":" and vim.fn.getcmdline():match("^[%s%d.$%%,;'<>+-]*hy$") then
		return "Hy"
	end
	return "hy"
end

function M.input(prompt, cb)
	vim.ui.input({ prompt = prompt }, function(value)
		if value and vim.fn.histget("@", -1) == value then
			vim.fn.histdel("@", -1)
		end
		cb(value)
	end)
end

function M.secret(prompt, cb)
	local ok, value = pcall(vim.fn.inputsecret, prompt)
	cb(ok and value or nil)
end

function M.get_text(bufnr, line1, line2)
	return table.concat(vim.api.nvim_buf_get_lines(bufnr, line1 - 1, line2, false), "\n")
end

function M.changedtick(bufnr)
	return vim.api.nvim_buf_get_changedtick(bufnr)
end

function M.clear(bufnr, line1, line2)
	vim.api.nvim_buf_set_lines(bufnr, line1 - 1, line2, false, {})
end

function M.close(bufnr)
	vim.api.nvim_buf_delete(bufnr, { force = true })
end

local function floats(win)
	local rects = {}
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		local cfg = vim.api.nvim_win_get_config(w)
		if w ~= win and cfg.relative ~= "" and not cfg.hide then
			local pos = vim.fn.win_screenpos(w)
			local b = type(cfg.border) == "table" and 1 or 0
			table.insert(rects, {
				pos[1] - b,
				pos[2] - b,
				pos[1] + vim.api.nvim_win_get_height(w) + b,
				pos[2] + vim.api.nvim_win_get_width(w) + b,
			})
		end
	end
	return rects
end

local function covered(rects, row, col)
	for _, q in ipairs(rects) do
		if row >= q[1] and row < q[3] and col >= q[2] and col < q[4] then
			return true
		end
	end
	return false
end

local function rows(win, lnum, wrap, leftcol)
	local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), lnum - 1, lnum, false)[1]
	if wrap then
		return vim.fn.screenpos(win, lnum, 1).row, vim.fn.screenpos(win, lnum, math.max(#line, 1)).row
	end
	local col = 1
	if leftcol > 0 then
		if vim.fn.exists("*virtcol2col") == 0 then
			return 0, 0
		end
		col = math.max(vim.fn.virtcol2col(win, lnum, leftcol + 1), 1)
	end
	local row = vim.fn.screenpos(win, lnum, col).row
	return row, row
end

function M.cells(win, line1, line2)
	local info = vim.fn.getwininfo(win)[1]
	local pos = vim.fn.win_screenpos(win)
	local wrap = vim.wo[win].wrap
	local leftcol = vim.api.nvim_win_call(win, vim.fn.winsaveview).leftcol
	local top, left = pos[1] + (info.winbar or 0), pos[2] + info.textoff
	local bottom, right = top + info.height - 1, pos[2] + info.width - 1
	local from = math.max(line1, info.topline)
	local to = math.min(line2, info.botline + 1, vim.api.nvim_buf_line_count(info.bufnr))
	local first = line1 <= info.topline and top or nil
	for lnum = from, to do
		if first then
			break
		end
		local row = rows(win, lnum, wrap, leftcol)
		first = row > 0 and row or nil
	end
	local last
	for lnum = to, from, -1 do
		local a, b = rows(win, lnum, wrap, leftcol)
		if b > 0 then
			last = b
		elseif a > 0 or (wrap and lnum == info.topline) then
			last = bottom
		end
		if last then
			break
		end
	end
	local cells = {}
	if not first or not last then
		return cells
	end
	local rects = floats(win)
	for row = first, math.min(last, bottom) do
		local col = left
		while col <= right do
			local ch = vim.fn.screenstring(row, col)
			local w = ch:match("^[ -~]$") and 1 or math.max(vim.fn.strdisplaywidth(ch), 1)
			if ch:match("%S") and not covered(rects, row, col) then
				table.insert(cells, { row = row - top, col = col - left, ch = ch, w = w })
			end
			col = col + w
		end
	end
	return cells
end

function M.utf16_len(s)
	local n = 0
	for i = 1, #s do
		local b = s:byte(i)
		if b < 0x80 or b >= 0xC0 then
			n = n + (b >= 0xF0 and 2 or 1)
		end
	end
	return n
end

local function split_long(piece, limit, chunks)
	local current, size = {}, 0
	for char in piece:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		local len = M.utf16_len(char)
		if size + len > limit then
			table.insert(chunks, table.concat(current))
			current, size = {}, 0
		end
		table.insert(current, char)
		size = size + len
	end
	return current, size
end

function M.split(text, limit)
	local chunks = {}
	local current, size = {}, 0
	for piece in (text .. "\n"):gmatch("(.-\n)") do
		local len = M.utf16_len(piece)
		if size + len > limit and size > 0 then
			table.insert(chunks, table.concat(current))
			current, size = {}, 0
		end
		if len > limit then
			current, size = split_long(piece, limit, chunks)
		else
			table.insert(current, piece)
			size = size + len
		end
	end
	table.insert(chunks, table.concat(current))
	local result = {}
	for _, chunk in ipairs(chunks) do
		local trimmed = chunk:gsub("^%s+", ""):gsub("%s+$", "")
		if trimmed ~= "" then
			table.insert(result, trimmed)
		end
	end
	return result
end

return M
