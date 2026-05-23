--- Stateful fuzzy scorer — port of fzf's algo.go scoring logic.
--- Pre-computed bonus matrix eliminates branch chains in the hot path.
---
---@class Beast.Finder.Score
---@field score number
---@field consecutive number
---@field prev? number
---@field prev_class number
---@field first_bonus number
---@field str string
---@field is_file boolean
local M = {}
M.__index = M

-- Scoring constants (fzf-compatible)
local SCORE_MATCH = 16
local SCORE_GAP_START = -3
local SCORE_GAP_EXTENSION = -1

local BONUS_BOUNDARY = SCORE_MATCH / 2 -- 8
local BONUS_NONWORD = SCORE_MATCH / 2 -- 8
local BONUS_CAMEL_123 = BONUS_BOUNDARY - 1 -- 7
local BONUS_CONSECUTIVE = -(SCORE_GAP_START + SCORE_GAP_EXTENSION) -- 4
local BONUS_FIRST_CHAR_MULTIPLIER = 2
local BONUS_NO_PATH_SEP = BONUS_BOUNDARY - 2 -- 6: match in filename portion

-- Character classes
local CHAR_WHITE = 0
local CHAR_NONWORD = 1
local CHAR_DELIMITER = 2
local CHAR_LOWER = 3
local CHAR_UPPER = 4
local CHAR_LETTER = 5
local CHAR_NUMBER = 6

-- Pre-computed class for all 256 byte values
local CHAR_CLASS = {} ---@type number[]
for b = 0, 255 do
	local c = CHAR_NONWORD
	local char = string.char(b)
	if char:match("%s") then
		c = CHAR_WHITE
	elseif char:match("[/\\,:;|]") then
		c = CHAR_DELIMITER
	elseif b >= 48 and b <= 57 then
		c = CHAR_NUMBER
	elseif b >= 65 and b <= 90 then
		c = CHAR_UPPER
	elseif b >= 97 and b <= 122 then
		c = CHAR_LOWER
	end
	CHAR_CLASS[b] = c
end

-- Pre-computed 7×7 bonus matrix
local BONUS_BOUNDARY_WHITE = BONUS_BOUNDARY + 2
local BONUS_BOUNDARY_DELIMITER = BONUS_BOUNDARY + 1

---@param prev number character class of previous char
---@param curr number character class of current char
---@return number bonus
local function compute_bonus(prev, curr)
	if curr > CHAR_NONWORD then
		if prev == CHAR_WHITE then
			return BONUS_BOUNDARY_WHITE
		elseif prev == CHAR_DELIMITER then
			return BONUS_BOUNDARY_DELIMITER
		elseif prev == CHAR_NONWORD then
			return BONUS_BOUNDARY
		end
	end
	-- camelCase or letter→number transitions
	if (prev == CHAR_LOWER and curr == CHAR_UPPER) or (prev ~= CHAR_NUMBER and curr == CHAR_NUMBER) then
		return BONUS_CAMEL_123
	end
	if curr == CHAR_NONWORD or curr == CHAR_DELIMITER then
		return BONUS_NONWORD
	elseif curr == CHAR_WHITE then
		return BONUS_BOUNDARY_WHITE
	end
	return 0
end

local BONUS_MATRIX = {} ---@type number[][]
for prev = 0, 6 do
	BONUS_MATRIX[prev] = {}
	for curr = 0, 6 do
		BONUS_MATRIX[prev][curr] = compute_bonus(prev, curr)
	end
end

-- Expose constants for external use
M.SCORE_MATCH = SCORE_MATCH
M.SCORE_GAP_START = SCORE_GAP_START
M.SCORE_GAP_EXTENSION = SCORE_GAP_EXTENSION
M.CHAR_CLASS = CHAR_CLASS

---@return Beast.Finder.Score
function M:new()
	return setmetatable({
		score = 0,
		consecutive = 0,
		prev = nil,
		prev_class = CHAR_WHITE,
		first_bonus = 0,
		str = "",
		is_file = true,
	}, self)
end

--- Initialize scoring for a new string starting at position `first`.
---@param str string the full haystack (original case for class detection)
---@param first number 1-based position of first matched char
function M:init(str, first)
	self.str = str
	self.score = 0
	self.consecutive = 0
	self.prev = nil
	self.first_bonus = 0
	if first > 1 then
		self.prev_class = CHAR_CLASS[str:byte(first - 1)] or CHAR_NONWORD
	else
		self.prev_class = CHAR_WHITE
	end
	-- Filename bonus: no path separator after match start
	if self.is_file and not str:find("/", first + 1, true) and not str:find("\\", first + 1, true) then
		self.score = self.score + BONUS_NO_PATH_SEP
	end
	self:update(first)
end

--- Score the next matched character at position `pos`.
---@param pos number 1-based position in self.str
function M:update(pos)
	local b = self.str:byte(pos)
	local class = CHAR_CLASS[b] or CHAR_NONWORD
	local bonus = 0
	local gap = self.prev and pos - self.prev - 1 or 0

	if gap > 0 then
		-- Gap penalty
		self.prev_class = CHAR_CLASS[self.str:byte(pos - 1)] or CHAR_NONWORD
		bonus = BONUS_MATRIX[self.prev_class][class] or 0
		self.score = self.score + SCORE_GAP_START + (gap - 1) * SCORE_GAP_EXTENSION
		self.consecutive = 0
		self.first_bonus = 0
	else
		bonus = BONUS_MATRIX[self.prev_class][class] or 0
		if self.consecutive == 0 then
			-- New consecutive chunk — store boundary bonus
			self.first_bonus = bonus
		else
			-- Upgrade chunk bonus if current boundary is stronger
			if bonus >= BONUS_BOUNDARY and bonus > self.first_bonus then
				self.first_bonus = bonus
			end
			bonus = math.max(bonus, self.first_bonus, BONUS_CONSECUTIVE)
		end
		self.consecutive = self.consecutive + 1
	end

	-- First matched character gets doubled bonus
	if not self.prev then
		bonus = bonus * BONUS_FIRST_CHAR_MULTIPLIER
	end

	self.score = self.score + SCORE_MATCH + bonus
	self.prev_class = class
	self.prev = pos
end

--- Score a contiguous range [from, to] in one call.
---@param str string the full haystack
---@param from number 1-based start
---@param to number 1-based end (inclusive)
---@return number score
function M:get(str, from, to)
	self:init(str, from)
	for i = from + 1, to do
		self:update(i)
	end
	return self.score
end

--- Check if `pos` is a left word boundary.
---@param str string
---@param pos number 1-based
---@return boolean
function M.is_left_boundary(str, pos)
	return pos == 1 or CHAR_CLASS[str:byte(pos - 1)] < CHAR_LOWER
end

--- Check if `pos` is a right word boundary.
---@param str string
---@param pos number 1-based
---@return boolean
function M.is_right_boundary(str, pos)
	return pos == #str or CHAR_CLASS[str:byte(pos + 1)] < CHAR_LOWER
end

return M
