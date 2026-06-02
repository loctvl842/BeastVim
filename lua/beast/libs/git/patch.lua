-- Unified-zero patch construction.
--
-- format(ref_lines, target_lines, hunks, path_data) -> string[]
--   Builds the same shape of patch `git apply --unidiff-zero` understands,
--   suitable for both staging (ref=index, target=buffer) and unstaging
--   (ref=HEAD, target=index, then apply --reverse).
--
-- Pattern follows mini.diff (lua/mini/diff.lua:1811-1840). Differences:
--   - our hunks use {a_*, b_*} not {ref_*, buf_*}; we re-map at the call site
--   - we receive plain line arrays (caller splits buffer/ref text)
--   - we accept a subset of hunks (so the caller can stage one out of N)

local M = {}

--- Build a unified-zero patch for `hunks`. Hunk positions are interpreted in
--- the spaces matching `ref_lines` (a_*) and `target_lines` (b_*); offsets are
--- accumulated so multi-hunk patches stay valid for sequential apply.
---@param ref_lines string[]    Reference side lines (index or HEAD)
---@param target_lines string[] Target side lines (buffer or index)
---@param hunks Beast.Git.RawHunk[] Hunks to include; iteration order matters
---@param path_data Beast.Git.PathData
---@return string[] patch_lines Caller appends "\n" between lines
function M.format(ref_lines, target_lines, hunks, path_data)
	local rel = path_data.rel_path
	local out = {
		string.format("diff --git a/%s b/%s", rel, rel),
		"index 000000..000000 " .. path_data.mode_bits,
		"--- a/" .. rel,
		"+++ b/" .. rel,
	}

	local cr = path_data.eol == "crlf" and "\r" or ""
	local offset = 0
	for i = 1, #hunks do
		local h = hunks[i]
		-- For pure-adds (a_count = 0), the header line is "above" the
		-- insertion point, so bump by 1 to match git's @@ convention.
		local hdr_start = h.a_start + (h.a_count == 0 and 1 or 0)
		out[#out + 1] = string.format("@@ -%d,%d +%d,%d @@", hdr_start, h.a_count, hdr_start + offset, h.b_count)
		for ln = h.a_start, h.a_start + h.a_count - 1 do
			out[#out + 1] = "-" .. (ref_lines[ln] or "") .. cr
		end
		for ln = h.b_start, h.b_start + h.b_count - 1 do
			out[#out + 1] = "+" .. (target_lines[ln] or "") .. cr
		end
		offset = offset + (h.b_count - h.a_count)
	end

	return out
end

return M
