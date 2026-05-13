--- Parser registry for beast.treesitter.
--- Maps language names to their GitHub repo URL, pinned revision, and optional metadata.
--- Revisions are pinned to match nvim-treesitter's query files for compatibility.
---
--- For unlisted languages, the installer falls back to the convention URL
--- (github.com/tree-sitter/tree-sitter-{lang}) with revision "HEAD".

---@class Beast.Treesitter.ParserInfo
---@field url string GitHub repo URL
---@field revision? string Git tag/branch/SHA (default: "HEAD")
---@field location? string Subdirectory within the repo containing the grammar

---@type table<string, Beast.Treesitter.ParserInfo>
local M = {
	-- Revisions pinned to nvim-treesitter compatibility
	c = {
		url = "https://github.com/tree-sitter/tree-sitter-c",
		revision = "ae19b676b13bdcc13b7665397e6d9b14975473dd",
	},
	cpp = {
		url = "https://github.com/tree-sitter/tree-sitter-cpp",
		revision = "8b5b49eb196bec7040441bee33b2c9a4838d6967",
	},
	lua = {
		url = "https://github.com/tree-sitter-grammars/tree-sitter-lua",
		revision = "10fe0054734eec83049514ea2e718b2a56acd0c9",
	},
	python = {
		url = "https://github.com/tree-sitter/tree-sitter-python",
		revision = "v0.25.0",
	},
	rust = {
		url = "https://github.com/tree-sitter/tree-sitter-rust",
		revision = "77a3747266f4d621d0757825e6b11edcbf991ca5",
	},
	javascript = {
		url = "https://github.com/tree-sitter/tree-sitter-javascript",
		revision = "58404d8cf191d69f2674a8fd507bd5776f46cb11",
	},
	typescript = {
		url = "https://github.com/tree-sitter/tree-sitter-typescript",
		revision = "75b3874edb2dc714fb1fd77a32013d0f8699989f",
		location = "typescript",
	},
	tsx = {
		url = "https://github.com/tree-sitter/tree-sitter-typescript",
		revision = "75b3874edb2dc714fb1fd77a32013d0f8699989f",
		location = "tsx",
	},
	go = {
		url = "https://github.com/tree-sitter/tree-sitter-go",
		revision = "2346a3ab1bb3857b48b29d779a1ef9799a248cd7",
	},
	java = {
		url = "https://github.com/tree-sitter/tree-sitter-java",
		revision = "e10607b45ff745f5f876bfa3e94fbcc6b44bdc11",
	},
	ruby = {
		url = "https://github.com/tree-sitter/tree-sitter-ruby",
		revision = "ad907a69da0c8a4f7a943a7fe012712208da6dee",
	},
	bash = {
		url = "https://github.com/tree-sitter/tree-sitter-bash",
		revision = "a06c2e4415e9bc0346c6b86d401879ffb44058f7",
	},
	json = {
		url = "https://github.com/tree-sitter/tree-sitter-json",
		revision = "001c28d7a29832b06b0e831ec77845553c89b56d",
	},
	html = {
		url = "https://github.com/tree-sitter/tree-sitter-html",
		revision = "73a3947324f6efddf9e17c0ea58d454843590cc0",
	},
	css = {
		url = "https://github.com/tree-sitter/tree-sitter-css",
		revision = "dda5cfc5722c429eaba1c910ca32c2c0c5bb1a3f",
	},
	toml = {
		url = "https://github.com/tree-sitter-grammars/tree-sitter-toml",
		revision = "64b56832c2cffe41758f28e05c756a3a98d16f41",
	},
	yaml = {
		url = "https://github.com/tree-sitter-grammars/tree-sitter-yaml",
		revision = "4463985dfccc640f3d6991e3396a2047610cf5f8",
	},
	regex = {
		url = "https://github.com/tree-sitter/tree-sitter-regex",
		revision = "b2ac15e27fce703d2f37a79ccd94a5c0cbe9720b",
	},
	markdown = {
		url = "https://github.com/tree-sitter-grammars/tree-sitter-markdown",
		revision = "f969cd3ae3f9fbd4e43205431d0ae286014c05b5",
		location = "tree-sitter-markdown",
	},
	markdown_inline = {
		url = "https://github.com/tree-sitter-grammars/tree-sitter-markdown",
		revision = "f969cd3ae3f9fbd4e43205431d0ae286014c05b5",
		location = "tree-sitter-markdown-inline",
	},
	vim = {
		url = "https://github.com/tree-sitter-grammars/tree-sitter-vim",
		revision = "3092fcd99eb87bbd0fc434aa03650ba58bd5b43b",
	},
	vimdoc = {
		url = "https://github.com/neovim/tree-sitter-vimdoc",
		revision = "f061895a0eff1d5b90e4fb60d21d87be3267031a",
	},
	query = {
		url = "https://github.com/tree-sitter-grammars/tree-sitter-query",
		revision = "fc5409c6820dd5e02b0b0a309d3da2bfcde2db17",
	},
	php = {
		url = "https://github.com/tree-sitter/tree-sitter-php",
		revision = "3f2465c217d0a966d41e584b42d75522f2a3149e",
		location = "php",
	},
	swift = {
		url = "https://github.com/alex-pinkus/tree-sitter-swift",
		revision = "8abb3e8b33256d89127a35e87480736f74755ff9",
	},
	kotlin = {
		url = "https://github.com/fwcd/tree-sitter-kotlin",
		revision = "93bfeee1555d2b1442d68c44b0afde2a3b069e46",
	},
	zig = {
		url = "https://github.com/tree-sitter-grammars/tree-sitter-zig",
		revision = "6479aa13f32f701c383083d8b28360ebd682fb7d",
	},
	elixir = {
		url = "https://github.com/elixir-lang/tree-sitter-elixir",
		revision = "7937d3b4d65fa574163cfa59394515d3c1cf16f4",
	},
	haskell = {
		url = "https://github.com/tree-sitter-grammars/tree-sitter-haskell",
		revision = "7fa19f195803a77855f036ee7f49e4b22856e338",
	},
	ocaml = {
		url = "https://github.com/tree-sitter/tree-sitter-ocaml",
		revision = "5a979b3ec7f1fe990b8e8c4412294a0cf7228e45",
		location = "grammars/ocaml",
	},
	scala = {
		url = "https://github.com/tree-sitter/tree-sitter-scala",
		revision = "14c5cfd2b8e0f057ba0f4f72ee4812b0ae6cdce3",
	},
	r = {
		url = "https://github.com/r-lib/tree-sitter-r",
		revision = "0e6ef7741712c09dc3ee6e81c42e919820cc65ef",
	},
	sql = {
		url = "https://github.com/derekstride/tree-sitter-sql",
		revision = "851e9cb257ba7c66cc8c14214a31c44d2f1e954e",
	},
	graphql = {
		url = "https://github.com/bkegley/tree-sitter-graphql",
		revision = "5e66e961eee421786bdda8495ed1db045e06b5fe",
	},
	dockerfile = {
		url = "https://github.com/camdencheek/tree-sitter-dockerfile",
		revision = "971acdd908568b4531b0ba28a445bf0bb720aba5",
	},
	make = {
		url = "https://github.com/tree-sitter-grammars/tree-sitter-make",
		revision = "70613f3d812cbabbd7f38d104d60a409c4008b43",
	},
	cmake = {
		url = "https://github.com/uyha/tree-sitter-cmake",
		revision = "c7b2a71e7f8ecb167fad4c97227c838439280175",
	},
	comment = {
		url = "https://github.com/stsewd/tree-sitter-comment",
		revision = "66272d2b6c73fb61157541b69dd0a7ce7b42a5ad",
	},
	diff = {
		url = "https://github.com/tree-sitter-grammars/tree-sitter-diff",
		revision = "2520c3f934b3179bb540d23e0ef45f75304b5fed",
	},
	git_rebase = {
		url = "https://github.com/the-mikedavis/tree-sitter-git-rebase",
		revision = "760ba8e34e7a68294ffb9c495e1388e030366188",
	},
	gitcommit = {
		url = "https://github.com/gbprod/tree-sitter-gitcommit",
		revision = "33fe8548abcc6e374feaac5724b5a2364bf23090",
	},
	gitignore = {
		url = "https://github.com/shunsambongi/tree-sitter-gitignore",
		revision = "f4685bf11ac466dd278449bcfe5fd014e94aa504",
	},
}

--- Look up parser info, falling back to convention URL.
---@param lang string
---@return Beast.Treesitter.ParserInfo
function M.get(lang)
	if M[lang] then
		return M[lang]
	end
	-- Convention: github.com/tree-sitter/tree-sitter-{lang}
	return {
		url = string.format("https://github.com/tree-sitter/tree-sitter-%s", lang),
	}
end

return M
