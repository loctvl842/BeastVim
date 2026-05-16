---@class Beast.Finder.Source.HelpTags: Beast.Finder.ASource
local M = {}

function M.get()
	local rtp = vim.o.runtimepath

	-- Collect all doc files and tag files from rtp (only loaded plugins)
	local help_files = {} ---@type table<string, string> filename -> fullpath
	local tag_file_paths = {} ---@type string[]
	local all_docs = vim.fn.globpath(rtp, "doc/*", true, true)
	for _, fullpath in ipairs(all_docs) do
		local file = vim.fn.fnamemodify(fullpath, ":t")
		if file == "tags" or file:match("^tags%-..$") then
			tag_file_paths[#tag_file_paths + 1] = fullpath
		else
			help_files[file] = fullpath
		end
	end

	-- Parse tag files
	local seen = {} ---@type table<string, boolean>
	local items = {}
	local idx = 0
	local vimruntime = vim.env.VIMRUNTIME or ""
	for _, tf in ipairs(tag_file_paths) do
		local is_plugin = tf:sub(1, #vimruntime) ~= vimruntime
		local ok, content = pcall(vim.fn.readfile, tf)
		if ok then
			for _, line in ipairs(content) do
				if not line:match("^!_TAG_") then
					local tag, filename = line:match("^([^\t]+)\t([^\t]+)\t")
					if tag and not seen[tag] then
						seen[tag] = true
						idx = idx + 1
						items[#items + 1] = {
							idx = idx,
							score = 0,
							text = tag,
							help_tag = tag,
							file = help_files[filename],
							is_plugin = is_plugin,
						}
					end
				end
			end
		end
	end

	-- Sort: plugins first, then builtin; within each group by filename > tag
	table.sort(items, function(a, b)
		if a.is_plugin ~= b.is_plugin then
			return a.is_plugin -- plugins come first
		end
		local fa = a.file or ""
		local fb = b.file or ""
		if fa ~= fb then
			return fa < fb
		end
		return a.text < b.text
	end)
	-- Re-index after sort
	for i, item in ipairs(items) do
		item.idx = i
	end
	return items
end

return M
