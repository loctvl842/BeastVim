if os.getenv("BEAST_PROFILE") == "1" then
	pcall(function()
		local profile = require("beast.profile")
		profile.start()
		local out = os.getenv("BEAST_PROFILE_OUT") or (vim.fn.stdpath("cache") .. "/beast-profile.txt")
		profile.auto_dump_on_quit(out)
	end)
end

require("beast").setup({
	key = {
		mappings = {
			{ "fd", "zd", desc = "Delete fold under cursor" },
			{ "fo", "zo", desc = "Open fold under cursor" },
			{ "fO", "zO", desc = "Open all folds under cursor" },
			{ "fc", "zC", desc = "Close all folds under cursor" },
			{ "fa", "za", desc = "Toggle fold under cursor" },
			{ "fA", "zA", desc = "Toggle all folds under cursor" },
			{ "fv", "zv", desc = "Show cursor line" },
			{ "fM", "zM", desc = "Close all folds" },
			{ "fR", "zR", desc = "Open all folds" },
			{ "fm", "zm", desc = "Fold more" },
			{ "fr", "zr", desc = "Fold less" },
			{ "fx", "zx", desc = "Update folds" },
			{ "fz", "zz", desc = "Center this line" },
			{ "ft", "zt", desc = "Top this line" },
			{ "fb", "zb", desc = "Bottom this line" },
			{ "fg", "zg", desc = "Add word to spell list" },
			{ "fw", "zw", desc = "Mark word as bad/misspelling" },
			{ "fe", "ze", desc = "Right this line" },
			{ "fE", "zE", desc = "Delete all folds in current buffer" },
			{ "fs", "zs", desc = "Left this line" },
			{ "fH", "zH", desc = "Half screen to the left" },
			{ "fL", "zL", desc = "Half screen to the right" },
		},
	},
	explorer = {
		icon = {
			dir_open = "󰝰", -- nf-md-folder_open
			dir_closed = "󰉋", -- nf-md-folder
			git = {
				conflict = "",
				deleted = "",
				added = "",
				renamed = "➜",
				modified = "●",
				untracked = "",
				ignored = "󱈸",
			},
		},
		mappings = {
			["l"] = "open",
		},
	},
	packer = {
		spec = { { import = "beast.plugins" } },
	},
	treesitter = {
		ensure_installed = { "python", "lua" },
		fold = { enable = true },
	},
})
