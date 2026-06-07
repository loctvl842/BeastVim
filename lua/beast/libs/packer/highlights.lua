local M = {}

function M.get()
	local p = Palette.get()
	return Util.colors.build("BeastPacker", {
		Backdrop = { bg = "#000000" },
		Normal = { bg = p.dark1, fg = p.dimmed1 },
		Border = { fg = p.dark1, bg = p.dark1 },
		WinBar = { bg = p.dark1 },
		Title = { fg = p.accent3, bold = true },
		Subtitle = { fg = p.dimmed2, bg = p.dark1 },
		H1 = { bg = p.accent2, fg = p.dark1, bold = true },
		H2 = { fg = p.dimmed1, bold = true },
		Comment = { fg = p.dimmed3 },

		-- Trigger types
		TriggerEager = { fg = p.accent1 },
		TriggerEvent = { fg = p.accent3 },
		TriggerKeys = { fg = p.accent5 },
		TriggerCmd = { fg = p.accent2 },
		TriggerModule = { fg = p.accent6 },
		TriggerFiletype = { fg = p.accent4 },
		TriggerPath = { fg = p.dimmed1 },

		-- UI elements
		Plugin = { fg = p.accent4 },
		Button = { bg = Util.colors.lighten(p.dark1, 20), fg = p.dimmed2 },
		ButtonActive = { bg = p.accent5, fg = p.dark1, bold = true },

		-- Status
		Warning = { fg = p.accent2 },
		Spinner = { fg = p.accent2 },
		Success = { fg = p.accent4 },
		Error = { fg = p.accent1 },

		Progress = { fg = p.accent3 },

		-- Profile page
		TableHeader = { fg = p.dimmed2, bold = true },
		Bar = { fg = p.accent3 },
		BarDim = { fg = p.dimmed3 },
		SectionDivider = { fg = p.dimmed3 },
		Checkpoint = { fg = p.accent4 },
		SummaryLabel = { fg = p.dimmed2 },
	})
end

return M
