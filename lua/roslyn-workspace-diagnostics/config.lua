local M = {}

---@class roslyn-workspace-diagnostics.Config
---@field enabled boolean
---@field roslyn_alias string[]
---@field csproj_watcher roslyn-workspace-diagnostics.CsprojWatcherConfig

---@class roslyn-workspace-diagnostics.CsprojWatcherConfig
---@field enabled boolean
---@field find_csproj_files? fun(path: string): string[]
M.defaults = {
	roslyn_alias = { "easy_dotnet", "roslyn_ls", "roslyn" },
	csproj_watcher = {
		enabled = false,
		find_csproj_files = nil,
	},
}

---@type roslyn-workspace-diagnostics.Config
M.options = {}

---@param opts? roslyn-workspace-diagnostics.Config
function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
