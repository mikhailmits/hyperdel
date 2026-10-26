local bit = require("bit")

local M = {}

local blocks = {
	{ 10, 1, 16, 0 },
	{ 16, 1, 28, 0 },
	{ 26, 1, 44, 0 },
	{ 18, 2, 32, 0 },
	{ 24, 2, 43, 0 },
	{ 16, 4, 27, 0 },
	{ 18, 4, 31, 0 },
	{ 22, 2, 38, 2 },
	{ 22, 3, 36, 2 },
	{ 26, 4, 43, 1 },
}

local alignment = {
	{},
	{ 6, 18 },
	{ 6, 22 },
	{ 6, 26 },
	{ 6, 30 },
	{ 6, 34 },
	{ 6, 22, 38 },
	{ 6, 24, 42 },
	{ 6, 26, 46 },
	{ 6, 28, 50 },
}

local masks = {
	function(x, y)
		return (x + y) % 2 == 0
	end,
	function(_, y)
		return y % 2 == 0
	end,
	function(x)
		return x % 3 == 0
	end,
	function(x, y)
		return (x + y) % 3 == 0
	end,
	function(x, y)
		return (math.floor(x / 3) + math.floor(y / 2)) % 2 == 0
	end,
	function(x, y)
		return x * y % 2 + x * y % 3 == 0
	end,
	function(x, y)
		return (x * y % 2 + x * y % 3) % 2 == 0
	end,
	function(x, y)
		return ((x + y) % 2 + x * y % 3) % 2 == 0
	end,
}

local exp, log = {}, {}
do
	local x = 1
	for i = 0, 254 do
		exp[i] = x
		log[x] = i
		x = x * 2
		if x >= 256 then
			x = bit.bxor(x, 0x11d)
		end
	end
end

local function mul(a, b)
	if a == 0 or b == 0 then
		return 0
	end
	return exp[(log[a] + log[b]) % 255]
end

local function ecc(data, n)
	local gen = { 1 }
	for i = 0, n - 1 do
		local next = {}
		for j = 1, #gen + 1 do
			next[j] = bit.bxor(gen[j] or 0, mul(gen[j - 1] or 0, exp[i]))
		end
		gen = next
	end
	local rem = {}
	for i = 1, n do
		rem[i] = 0
	end
	for _, byte in ipairs(data) do
		local factor = bit.bxor(byte, rem[1])
		table.remove(rem, 1)
		rem[n] = 0
		for i = 1, n do
			rem[i] = bit.bxor(rem[i], mul(gen[i + 1], factor))
		end
	end
	return rem
end

local function codewords(text, version, spec)
	local count = spec[2] + spec[4]
	local capacity = (spec[2] * spec[3] + spec[4] * (spec[3] + 1)) * 8
	local bits = {}
	local function put(value, len)
		for i = len - 1, 0, -1 do
			table.insert(bits, bit.band(bit.rshift(value, i), 1))
		end
	end
	put(4, 4)
	put(#text, version < 10 and 8 or 16)
	for i = 1, #text do
		put(text:byte(i), 8)
	end
	put(0, math.min(4, capacity - #bits))
	put(0, (8 - #bits % 8) % 8)
	local pad = 0
	while #bits < capacity do
		put(pad % 2 == 0 and 0xEC or 0x11, 8)
		pad = pad + 1
	end
	local bytes = {}
	for i = 1, #bits, 8 do
		local v = 0
		for k = 0, 7 do
			v = v * 2 + bits[i + k]
		end
		table.insert(bytes, v)
	end
	local data, ec, pos = {}, {}, 1
	for b = 1, count do
		local len = spec[3] + (b > spec[2] and 1 or 0)
		data[b] = { unpack(bytes, pos, pos + len - 1) }
		ec[b] = ecc(data[b], spec[1])
		pos = pos + len
	end
	local out = {}
	for i = 1, spec[3] + 1 do
		for b = 1, count do
			if data[b][i] then
				table.insert(out, data[b][i])
			end
		end
	end
	for i = 1, spec[1] do
		for b = 1, count do
			table.insert(out, ec[b][i])
		end
	end
	return out
end

local function penalty(grid, size)
	local score, dark = 0, 0
	local function scan(get)
		for i = 0, size - 1 do
			local run, prev, line = 0, nil, {}
			for j = 0, size - 1 do
				local v = get(i, j)
				line[j + 1] = v and "1" or "0"
				if v == prev then
					run = run + 1
					score = score + (run == 5 and 3 or run > 5 and 1 or 0)
				else
					prev, run = v, 1
				end
			end
			line = table.concat(line)
			for j = 1, size - 10 do
				local s = line:sub(j, j + 10)
				if s == "10111010000" or s == "00001011101" then
					score = score + 40
				end
			end
		end
	end
	scan(function(i, j)
		return grid[i][j]
	end)
	scan(function(i, j)
		return grid[j][i]
	end)
	for y = 0, size - 1 do
		for x = 0, size - 1 do
			local v = grid[y][x]
			if v then
				dark = dark + 1
			end
			if x < size - 1 and y < size - 1 and v == grid[y][x + 1] and v == grid[y + 1][x] and v == grid[y + 1][x + 1] then
				score = score + 3
			end
		end
	end
	return score + 10 * math.floor(math.abs(dark * 100 / (size * size) - 50) / 5)
end

function M.encode(text)
	local version, spec
	for v, s in ipairs(blocks) do
		local bytes = s[2] * s[3] + s[4] * (s[3] + 1)
		if 4 + (v < 10 and 8 or 16) + 8 * #text <= bytes * 8 then
			version, spec = v, s
			break
		end
	end
	if not version then
		return nil
	end

	local size = 17 + 4 * version
	local grid, fixed = {}, {}
	for y = 0, size - 1 do
		grid[y], fixed[y] = {}, {}
		for x = 0, size - 1 do
			grid[y][x] = false
		end
	end
	local function set(x, y, dark)
		grid[y][x] = dark
		fixed[y][x] = true
	end

	for i = 0, size - 1 do
		set(6, i, i % 2 == 0)
		set(i, 6, i % 2 == 0)
	end
	for _, c in ipairs({ { 3, 3 }, { size - 4, 3 }, { 3, size - 4 } }) do
		for dy = -4, 4 do
			for dx = -4, 4 do
				local x, y = c[1] + dx, c[2] + dy
				if x >= 0 and x < size and y >= 0 and y < size then
					local d = math.max(math.abs(dx), math.abs(dy))
					set(x, y, d ~= 2 and d ~= 4)
				end
			end
		end
	end
	local a = alignment[version]
	for i = 1, #a do
		for j = 1, #a do
			if not ((i == 1 and j == 1) or (i == 1 and j == #a) or (i == #a and j == 1)) then
				for dy = -2, 2 do
					for dx = -2, 2 do
						set(a[i] + dx, a[j] + dy, math.max(math.abs(dx), math.abs(dy)) ~= 1)
					end
				end
			end
		end
	end

	local function format(mask)
		local rem = mask
		for _ = 1, 10 do
			rem = bit.bxor(bit.lshift(rem, 1), bit.rshift(rem, 9) * 0x537)
		end
		local bits = bit.bxor(bit.bor(bit.lshift(mask, 10), rem), 0x5412)
		local function at(i)
			return bit.band(bit.rshift(bits, i), 1) == 1
		end
		for i = 0, 5 do
			set(8, i, at(i))
		end
		set(8, 7, at(6))
		set(8, 8, at(7))
		set(7, 8, at(8))
		for i = 9, 14 do
			set(14 - i, 8, at(i))
		end
		for i = 0, 7 do
			set(size - 1 - i, 8, at(i))
		end
		for i = 8, 14 do
			set(8, size - 15 + i, at(i))
		end
		set(8, size - 8, true)
	end
	format(0)

	if version >= 7 then
		local rem = version
		for _ = 1, 12 do
			rem = bit.bxor(bit.lshift(rem, 1), bit.rshift(rem, 11) * 0x1F25)
		end
		local bits = bit.bor(bit.lshift(version, 12), rem)
		for i = 0, 17 do
			local dark = bit.band(bit.rshift(bits, i), 1) == 1
			local p, q = size - 11 + i % 3, math.floor(i / 3)
			set(p, q, dark)
			set(q, p, dark)
		end
	end

	local data = codewords(text, version, spec)
	local i = 0
	local right = size - 1
	while right >= 1 do
		if right == 6 then
			right = 5
		end
		for vert = 0, size - 1 do
			for j = 0, 1 do
				local x = right - j
				local y = bit.band(right + 1, 2) == 0 and size - 1 - vert or vert
				if not fixed[y][x] and i < #data * 8 then
					local byte = data[bit.rshift(i, 3) + 1]
					grid[y][x] = bit.band(bit.rshift(byte, 7 - bit.band(i, 7)), 1) == 1
					i = i + 1
				end
			end
		end
		right = right - 2
	end

	local function apply(mask)
		for y = 0, size - 1 do
			for x = 0, size - 1 do
				if not fixed[y][x] and masks[mask + 1](x, y) then
					grid[y][x] = not grid[y][x]
				end
			end
		end
	end
	local best, lowest
	for mask = 0, 7 do
		apply(mask)
		format(mask)
		local score = penalty(grid, size)
		if not lowest or score < lowest then
			best, lowest = mask, score
		end
		apply(mask)
	end
	apply(best)
	format(best)
	return grid, size
end

function M.render(text)
	local grid, size = M.encode(text)
	if not grid then
		return nil
	end
	local function dark(x, y)
		return y >= 0 and y < size and x >= 0 and x < size and grid[y][x]
	end
	local lines = {}
	for y = -2, size + 1, 2 do
		local chars = {}
		for x = -2, size + 1 do
			local top, bottom = dark(x, y), dark(x, y + 1)
			chars[#chars + 1] = top and bottom and "█" or top and "▀" or bottom and "▄" or " "
		end
		table.insert(lines, table.concat(chars))
	end
	return lines
end

return M
