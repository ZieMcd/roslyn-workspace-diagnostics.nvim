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
			local client_id = args.data.client_id
			local client = vim.lsp.get_client_by_id(client_id)
			if not client or not vim.tbl_contains(config.options.roslyn_alias, client.name) then
				return
			end

			if args.data.method == "textDocument/didOpen" then
				diagnostics._track_open(client_id, args.data.params.textDocument.uri)
				return
			end

			if args.data.method == "textDocument/didClose" then
				diagnostics._track_close(client_id, args.data.params.textDocument.uri)
				return
			end

			-- every time we update
			if args.data.method == "textDocument/didChange" then
				local prev_reqeust = pending_requests[client_id]
				if prev_reqeust then
					-- -- for some reason cancelling the request was causing some odd behaviour.
					-- client:cancel_request(prev_reqeust.request_id)
					active_tokens[prev_reqeust.token] = nil
				end

				local token = "roslyn-workspace-pull-" .. vim.uv.hrtime()
				active_tokens[token] = true

				local _, request_id = client:request("workspace/diagnostic", {
					previousResultIds = diagnostics._build_previous_result_ids(client_id),
					-- for now will only call diagnostics for WorkspaceDocumentsAndProject since it is bulk of diagnostic. In future can call diagnostics for for other types
					identifier = diagnostics_identifier.WorkspaceDocumentsAndProject,
					partialResultToken = token,
				}, function(err, result, ctx, _)
					pending_requests[client_id] = nil
					active_tokens[token] = nil
					diagnostics.handle_workspace_result(err, result, ctx, _)
				end)

				pending_requests[client_id] = { request_id = request_id, token = token }
			end
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
end

return M
