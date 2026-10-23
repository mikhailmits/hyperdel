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

function M.input(prompt, cb)
	vim.ui.input({ prompt = prompt }, cb)
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
