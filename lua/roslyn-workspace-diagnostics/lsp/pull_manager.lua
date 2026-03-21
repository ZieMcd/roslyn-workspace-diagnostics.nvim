local diagnostics = require("roslyn-workspace-diagnostics.lsp.diagnostics")
local diagnostics_identifier = require("roslyn-workspace-diagnostics.lsp.roslyn_diagnostic_identifiers")
local config = require("roslyn-workspace-diagnostics.config")

local M = {}

---@type table<integer, uv.uv_timer_t>
local client_timers = {}

---@type table<string, boolean>
M.active_request_tokens = {}

function M._stop_pulling(client_id)
	if client_timers[client_id] then
		client_timers[client_id]:stop()
		client_timers[client_id]:close()
		client_timers[client_id] = nil
	end
end

function M._schedule_next_pull(client_id, is_refresh)
	if is_refresh and config.options.on_diagnostic_refresh_start then
		config.options.on_diagnostic_refresh_start(client_id)
	end
	if not client_timers[client_id] then
		client_timers[client_id] = vim.uv.new_timer()
	end
	local client_timer = client_timers[client_id]
	if not client_timer then
		return
	end
	client_timer:start(
		2000,
		0,
		vim.schedule_wrap(function()
			M._request_workspace_diagnostics(client_id, is_refresh)
		end)
	)
end

function M._request_workspace_diagnostics(client_id, is_refresh)
	local client = vim.lsp.get_client_by_id(client_id)

	if not client then
		return
	end

	local token = "roslyn-workspace-pull-" .. vim.uv.hrtime()
	M.active_request_tokens[token] = true

	client:request("workspace/diagnostic", {
		previousResultIds = diagnostics._build_previous_result_ids(client.id),
		identifier = diagnostics_identifier.WorkspaceDocumentsAndProject,
		partialResultToken = token,
	}, function(err, result, ctx, _)
		M.active_request_tokens[token] = nil
		diagnostics.handle_workspace_result(err, result, ctx, diagnostics_identifier.WorkspaceDocumentsAndProject)
		if is_refresh and config.options.on_diagnostic_refresh_finish then
			config.options.on_diagnostic_refresh_finish(client_id)
		end
		M._schedule_next_pull(client_id, false)
	end)
end

return M
