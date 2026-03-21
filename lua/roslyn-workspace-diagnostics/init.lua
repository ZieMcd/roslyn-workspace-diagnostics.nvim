local M = {}

local pull_manager = require("roslyn-workspace-diagnostics.lsp.pull_manager")
local diagnostics = require("roslyn-workspace-diagnostics.lsp.diagnostics")
local config = require("roslyn-workspace-diagnostics.config")
local watcher = require("roslyn-workspace-diagnostics.lsp.watcher")

---@param opts? roslyn-workspace-diagnostics.Config
function M.setup(opts)
	config.setup(opts)
	diagnostics.onWorkspaceComplete(function(client_id)
		pull_manager._schedule_next_pull(client_id)
	end)

	vim.api.nvim_create_autocmd("LspDetach", {
		callback = function(args)
			pull_manager._stop_pulling(args.data.client_id)
		end,
	})

	if config.options.csproj_watcher.enabled then
		watcher.start()
	end
end

return M
