local M = {}

local function set_hl(name, spec)
	-- If link is provided, use link (don’t mix with fg/bg)
	if spec.link then
		vim.api.nvim_set_hl(0, name, { link = spec.link })
	else
		vim.api.nvim_set_hl(0, name, spec)
	end
end

function M.defaults()
	-- Keep these conservative: either links or simple styles
	return {
    BeastH2 = { link = "Title" },
    BeastComment = { link = "Comment" },
    BeastGroup = { link = "Title" },
    BeastKeys = { link = "Comment" },
	}
end

function M.apply(user_overrides)
	local groups = vim.tbl_deep_extend("force", M.defaults(), user_overrides or {})

	for name, spec in pairs(groups) do
		set_hl(name, spec)
	end
end

return M
