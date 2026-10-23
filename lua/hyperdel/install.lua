local ffi = require("ffi")
local library = require("hyperdel.tdlib.library")
local nvim = require("hyperdel.nvim")

local uv = vim.uv or vim.loop

local M = {}

M.npm_version = "0.1008069.0"
M.tdlib_version = "1.8.69"

local sha512 = {
	["darwin-arm64"] = "3d839d37fc925dea779b2f94849e990b0dc7354ea19787c16ed42496ff89b2797553faf2f9e4024b8fcb255bf2b0875351ae0386f4943d27fe95004fb79b4966",
	["darwin-x64"] = "f0b223cf89fbfd2b3641d4b5cefb3684524dde94db9d74747a08756603377f0d05ea51149d1c8985de5233ed38bfb9aa7074b5ee53ef3c2eb7b3583cd48bfe0a",
	["linux-x64-glibc"] = "c555cd6ddb8efdb4becc8be3cbfc794629a612e69fe3a0d606bc410db547090fe3a3fa2f13094bc882ca5ffd41e795c73a4d7be374c51a1e9d5eb782e8f9b240",
	["linux-x64-musl"] = "5a60425e135ab45515929546db24b7b021a13377de5c706fad607c94915beb52ba330fd00b1101da292b120ce8f8d383a4ae39caf53f8f51906facade7aa4b9b",
	["linux-arm64-glibc"] = "ec5dff8a041980a8c3b21ab00d13c8f4604512d9a846aae667245dae731c636d7e6bcd29c4b3a9f83a41f61cf2709834b16dd2a9276378b45575a09774117b67",
	["linux-arm64-musl"] = "dac55a5104abc6acfdf30cabfd2c775741de8ab420c5ca6cc783541dc7c73289f92a067f250ddbca3b157bd020e853fc7726840191115330e6b5f15731b30d2b",
	["win32-x64"] = "a97c948834b77b5750918347b534b56a5bf89b7881270406c5ca181849eb3cbabb7e318c7387b77e3d7e625c4c0d5401b05f9e19bb1e8768fed4ffc50a691a06",
}

function M.platform()
	local arch = ({ arm64 = "arm64", x64 = "x64" })[ffi.arch]
	if not arch then
		return nil, "unsupported CPU architecture " .. ffi.arch
	end
	if ffi.os == "OSX" then
		return "darwin-" .. arch
	elseif ffi.os == "Windows" and arch == "x64" then
		return "win32-x64"
	elseif ffi.os == "Linux" then
		local libc = vim.fn.glob("/lib/ld-musl-*") ~= "" and "musl" or "glibc"
		return "linux-" .. arch .. "-" .. libc
	end
	return nil, "unsupported platform " .. ffi.os .. " " .. ffi.arch
end

function M.url(platform)
	return string.format("https://registry.npmjs.org/@prebuilt-tdlib/%s/-/%s-%s.tgz", platform, platform, M.npm_version)
end

local function run(cmd)
	local out = vim.fn.system(cmd)
	if vim.v.shell_error ~= 0 then
		return nil, table.concat(cmd, " ") .. " failed: " .. out
	end
	return out
end

local function hash_command(file)
	if vim.fn.executable("shasum") == 1 then
		return { "shasum", "-a", "512", file }
	elseif vim.fn.executable("sha512sum") == 1 then
		return { "sha512sum", file }
	elseif vim.fn.executable("openssl") == 1 then
		return { "openssl", "dgst", "-sha512", file }
	elseif vim.fn.executable("certutil") == 1 then
		return { "certutil", "-hashfile", file, "SHA512" }
	end
end

local function verify(file, expected)
	local cmd = hash_command(file)
	if not cmd then
		return nil, "no sha512 tool found (shasum, sha512sum, openssl or certutil)"
	end
	local out, err = run(cmd)
	if not out then
		return nil, err
	end
	for hex in out:lower():gmatch("%x+") do
		if #hex == 128 then
			if hex == expected then
				return true
			end
			return nil, "checksum mismatch for " .. file
		end
	end
	return nil, "could not read checksum output: " .. out
end

local function installed_version()
	local version_file = library.install_dir() .. "/VERSION"
	if vim.fn.filereadable(version_file) == 0 then
		return nil
	end
	return vim.fn.readfile(version_file)[1]
end

local function is_library(path)
	return path:match("%.dylib$") or path:match("%.dll$") or path:match("%.so[%.%d]*$")
end

function M.install(force)
	local platform, platform_err = M.platform()
	if not platform then
		return nil, platform_err
	end
	local dir = library.install_dir()
	local target = dir .. "/" .. library.filename()
	if not force and installed_version() == M.tdlib_version and vim.fn.filereadable(target) == 1 then
		return true, "TDLib " .. M.tdlib_version .. " already installed"
	end
	for _, tool in ipairs({ "curl", "tar" }) do
		if vim.fn.executable(tool) == 0 then
			return nil, tool .. " is required to install TDLib"
		end
	end
	local tmp = vim.fn.tempname()
	vim.fn.mkdir(tmp, "p")
	local archive = tmp .. "/tdlib.tgz"
	local ok, err = run({ "curl", "-fsSL", "-o", archive, M.url(platform) })
	if ok then
		ok, err = verify(archive, sha512[platform])
	end
	if ok then
		ok, err = run({ "tar", "-xzf", archive, "-C", tmp })
	end
	if ok then
		vim.fn.mkdir(dir, "p")
		local copied = 0
		for _, path in ipairs(vim.fn.globpath(tmp, "**/*", false, true)) do
			if is_library(path) and vim.fn.isdirectory(path) == 0 then
				local dest = dir .. "/" .. vim.fn.fnamemodify(path, ":t")
				uv.fs_unlink(dest)
				local success, copy_err = uv.fs_copyfile(path, dest)
				if not success then
					ok, err = nil, copy_err
					break
				end
				copied = copied + 1
			end
		end
		if ok and vim.fn.filereadable(target) == 0 then
			ok, err = nil, library.filename() .. " not found in the " .. platform .. " package"
		elseif ok and copied > 0 then
			vim.fn.writefile({ M.tdlib_version }, dir .. "/VERSION")
		end
	end
	vim.fn.delete(tmp, "rf")
	if not ok then
		return nil, err
	end
	return true, "installed TDLib " .. M.tdlib_version .. " (" .. platform .. ") into " .. dir
end

function M.run(opts)
	opts = opts or {}
	nvim.notify("installing TDLib " .. M.tdlib_version .. "...")
	local ok, msg = M.install(opts.force)
	if ok then
		nvim.notify(msg)
	else
		nvim.error(msg)
	end
	return ok, msg
end

return M
