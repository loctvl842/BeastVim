local M = {}

---@param _filter Beast.Finder.Filter
---@return Beast.Finder.Item[]
function M.get(_filter)
	local rtp = vim.o.runtimepath
	-- Include lazy-loaded plugin paths if available
	local lazy_util = package.loaded["lazy.core.util"]
	if lazy_util and lazy_util.get_unloaded_rtp then
		local paths = lazy_util.get_unloaded_rtp("")
		rtp = rtp .. "," .. table.concat(paths, ",")
	end
	-- Include opt plugins not yet in rtp (BeastVim packer)
	local opt_dir = vim.fn.stdpath("data") .. "/site/pack/core/opt"
	local opt_plugins = vim.fn.globpath(opt_dir, "*", 1, 1)
	local plugins_with_tags = {} ---@type table<string, boolean>
	for _, plugin_path in ipairs(opt_plugins) do
		if not rtp:find(plugin_path, 1, true) then
			rtp = rtp .. "," .. plugin_path
		end
	end

	-- Collect all doc files and tag files from rtp
	local help_files = {} ---@type table<string, string> filename -> fullpath
	local tag_file_paths = {} ---@type string[]
	local all_docs = vim.fn.globpath(rtp, "doc/*", 1, 1)
	for _, fullpath in ipairs(all_docs) do
		local file = vim.fn.fnamemodify(fullpath, ":t")
		if file == "tags" or file:match("^tags%-..$") then
			tag_file_paths[#tag_file_paths + 1] = fullpath
			-- Track which plugin dirs have tags
			local plugin_dir = fullpath:match("^(.+)/doc/tags")
			if plugin_dir then
				plugins_with_tags[plugin_dir] = true
			end
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

	-- Fallback: plugins without doc/tags get an entry pointing to README
	for _, plugin_path in ipairs(opt_plugins) do
		if not plugins_with_tags[plugin_path] then
			local name = vim.fn.fnamemodify(plugin_path, ":t")
			local readme = nil
			for _, candidate in ipairs({ "README.md", "readme.md", "README.rst", "README.txt" }) do
				local path = plugin_path .. "/" .. candidate
				if vim.fn.filereadable(path) == 1 then
					readme = path
					break
				end
			end
			if readme then
				-- Parse markdown headings as sections
				local ok_read, content = pcall(vim.fn.readfile, readme)
				if ok_read then
					for lnum, line in ipairs(content) do
						local heading = line:match("^(#+)%s+(.+)")
						if heading then
							local section = line:match("^#+%s+(.+)")
							idx = idx + 1
							items[#items + 1] = {
								idx = idx,
								score = 0,
								text = name .. ": " .. section,
								help_tag = name,
								file = readme,
								pos = { lnum, 0 },
								is_plugin = true,
								is_readme = true,
							}
						end
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
