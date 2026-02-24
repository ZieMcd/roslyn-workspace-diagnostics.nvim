local M = {}

---@class sharpies.Config
---@field enabled boolean
M.defaults = {
	enabled = true,
}

---@type sharpies.Config
M.options = {}

---@param opts? sharpies.Config
function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
