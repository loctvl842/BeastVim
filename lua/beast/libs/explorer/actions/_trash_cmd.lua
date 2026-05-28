local M = {}

---@param path string
---@return string[][]
local function get_cmds(path)
	local ret = {
		{ "trash", path }, -- trash-cli / macOS Homebrew `trash`
		{ "gio", "trash", path }, -- GLib (most Linux desktops)
		{ "kioclient5", "move", path, "trash:/" }, -- KDE Plasma 5
		{ "kioclient", "move", path, "trash:/" }, -- KDE Plasma 6
	}
	if vim.fn.has("mac") == 1 then
		-- AppleScript fallback: works without any extra CLI installed.
		local escaped = path:gsub("\\", "\\\\"):gsub('"', '\\"')
		table.insert(ret, {
			"osascript",
			"-e",
			string.format('tell application "Finder" to delete POSIX file "%s"', escaped),
		})
	end
	if vim.fn.has("win32") == 1 then
		local ps_path = path:gsub("\\", "\\\\"):gsub("'", "''")
		local kind = vim.fn.isdirectory(path) == 0 and "DeleteFile" or "DeleteDirectory"
		table.insert(ret, {
			"powershell",
			"-NoProfile",
			"-Command",
			"Add-Type -AssemblyName Microsoft.VisualBasic; "
				.. "[Microsoft.VisualBasic.FileIO.FileSystem]::"
				.. kind
				.. "('"
				.. ps_path
				.. "','OnlyErrorDialogs','SendToRecycleBin')",
		})
	end
	return ret
end

---@param path string
---@return boolean ok, string? err
function M.move(path)
	for _, cmd in ipairs(get_cmds(path)) do
		if vim.fn.executable(cmd[1]) == 1 then
			local ok, ret = pcall(vim.fn.system, cmd)
			if not ok or vim.v.shell_error ~= 0 then
				return false,
					string.format(
						"- cmd: `%s`\n- error: %s",
						table.concat(cmd, " "),
						type(ret) == "string" and ret or "Unknown error"
					)
			end
			return true
		end
	end
	return false, "No trash command available (install `trash`, `gio`, or run on macOS/Windows)"
end

return M
