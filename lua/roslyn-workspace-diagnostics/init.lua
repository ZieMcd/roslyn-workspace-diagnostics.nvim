local M = {}

local diagnostics_identifier = require("roslyn-workspace-diagnostics.lsp.roslyn_diagnostic_identifiers")
local config = require("roslyn-workspace-diagnostics.config")
local diagnostics = require("roslyn-workspace-diagnostics.lsp.diagnostics")
local watcher = require("roslyn-workspace-diagnostics.lsp.watcher")

local active_tokens = {}
local pending_requests = {}

local function register_progress_handler()
	local original = vim.lsp.handlers["$/progress"]

	vim.lsp.handlers["$/progress"] = function(err, result, ctx, handler_config)
		if active_tokens[result[1]] then
			diagnostics.handle_workspace_result(nil, result[2], { client_id = ctx.client_id }, nil)
			return
		end

		if original then
			original(err, result, ctx, handler_config)
		end
	end
end

local function register_autocmds()
	vim.api.nvim_create_autocmd("LspNotify", {
		callback = function(args)
			if args.data.method ~= "textDocument/didChange" then
				return
			end

			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if not client then
				return
			end

			if not vim.tbl_contains(config.options.roslyn_alias, client.name) then
				return
			end

			local prev_reqeust = pending_requests[args.data.client_id]
			if prev_reqeust then
				client:cancel_request(prev_reqeust.request_id)
				active_tokens[prev_reqeust.token] = nil
			end

			local token = "roslyn-workspace-pull-" .. vim.uv.hrtime()
			active_tokens[token] = true

			local _, request_id = client:request("workspace/diagnostic", {
				previousResultIds = diagnostics.build_previous_result_ids(args.data.client_id),
				-- for now will only call diagnostics for WorkspaceDocumentsAndProject since it is bulk of diagnostic. In future can call diagnostics for for other types
				identifier = diagnostics_identifier.WorkspaceDocumentsAndProject,
				partialResultToken = token,
			}, function(err, result, ctx, _)
				pending_requests[args.data.client_id] = nil
				active_tokens[token] = nil
				diagnostics.handle_workspace_result(err, result, ctx, _)
			end)

			pending_requests[args.data.client_id] = { request_id = request_id, token = token }
		end,
	})
end

---@param opts? roslyn-workspace-diagnostics.Config
function M.setup(opts)
	config.setup(opts)
	register_progress_handler()
	register_autocmds()
	if config.options.csproj_watcher.enabled then
		watcher.start()
	end

	vim.keymap.set("n", "<leader>pd", function()
		local clients = vim.lsp.get_clients({ bufnr = 0 })
		for _, client in ipairs(clients) do
			if vim.tbl_contains(config.options.roslyn_alias, client.name) then
				local result_ids = diagnostics.build_previous_result_ids(client.id)
				local lines = vim.split(vim.inspect(result_ids), "\n")
				local buf = vim.api.nvim_create_buf(false, true)
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
				vim.cmd.sbuffer(buf)
				return
			end
		end
		vim.notify("roslyn client not found", vim.log.levels.WARN)
	end)
end

return M
