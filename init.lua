if os.getenv("BEAST_PROFILE") == "1" then
	pcall(function()
		local profile = require("beast.profile")
		profile.start()
		local out = os.getenv("BEAST_PROFILE_OUT") or (vim.fn.stdpath("cache") .. "/beast-profile.txt")
		profile.auto_dump_on_quit(out)
	end)
end

require("beast").setup()
