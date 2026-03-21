local M = {}

local pull_manager = require("roslyn-workspace-diagnostics.lsp.pull_manager")
local config = require("roslyn-workspace-diagnostics.config")
local diagnostics = require("roslyn-workspace-diagnostics.lsp.diagnostics")
local watcher = require("roslyn-workspace-diagnostics.lsp.watcher")
local diagnostics_identifier = require("roslyn-workspace-diagnostics.lsp.roslyn_diagnostic_identifiers")

local function register_handlers()
	local original_refresh = vim.lsp.handlers["workspace/diagnostic/refresh"]

	vim.lsp.handlers["workspace/diagnostic/refresh"] = function(err, result, ctx, handler_config)
		local client = vim.lsp.get_client_by_id(ctx.client_id)

		if client and vim.tbl_contains(config.options.roslyn_alias, client.name) then
			pull_manager._stop_pulling(ctx.client_id)
			diagnostics._reset_result_ids(ctx.client_id)
			pull_manager._schedule_next_pull(ctx.client_id, true)
			return vim.NIL
		end

		if original_refresh then
			return original_refresh(err, result, ctx, handler_config)
		end
		return vim.NIL
	end
end

local function register_progress_handler()
	local original = vim.lsp.handlers["$/progress"]

	vim.lsp.handlers["$/progress"] = function(err, result, ctx, handler_config)
		if pull_manager.active_request_tokens[result[1]] then
			diagnostics.handle_workspace_result(
				nil,
				result[2],
				{ client_id = ctx.client_id },
				diagnostics_identifier.WorkspaceDocumentsAndProject
			)
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

			--Neovim only pull diagnostics for open files, and workspace diagnostics does not return anything for open files.
			--So we pull diagnostics for all open files
			if args.data.method == "textDocument/didChange" then
				diagnostics._refresh_open_files(client_id)
				return
			end
		end,
	})

	vim.api.nvim_create_autocmd("LspDetach", {
		callback = function(args)
			local client_id = args.data.client_id
			pull_manager._stop_pulling(client_id)
			diagnostics._reset_result_ids(client_id)
			local ns = vim.lsp.diagnostic.get_namespace(client_id, true)
			vim.diagnostic.reset(ns)
		end,
	})
end

---@param opts? roslyn-workspace-diagnostics.Config
function M.setup(opts)
	config.setup(opts)
	register_progress_handler()
	register_autocmds()
	register_handlers()
	if config.options.csproj_watcher.enabled then
		watcher.start()
	end
end

return M
