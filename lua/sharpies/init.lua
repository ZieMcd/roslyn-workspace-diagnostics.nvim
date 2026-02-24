local M = {}

local config = require("sharpies.config")
local diagnostics = require("sharpies.diagnostics")

local active_tokens = {}
local pending_requests = {}
local all_items = {}
local opened_files = {}

local function register_progress_handler()
	local original = vim.lsp.handlers["$/progress"]

	vim.lsp.handlers["$/progress"] = function(err, result, ctx, handler_config)
		if active_tokens[result[1]] then
			-- vim.notify(vim.inspect(result))
			table.insert(all_items, result)
			-- vim.notify("sharpies: $/progress partial result for token=" .. tostring(result.token))
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
			local method = args.data.method
			if method == "textDocument/didOpen" then
				vim.notify(vim.inspect(args))
				opened_files[args.data.params.textDocument.uri] = true
			elseif method == "textDocument/didClose" then
				vim.notify(vim.inspect(args))
				opened_files[args.data.params.textDocument.uri] = nil
			end
			-- end
		end,
	})

	vim.api.nvim_create_autocmd("LspNotify", {
		callback = function(args)
			if args.data.method ~= "textDocument/didChange" then
				return
			end

			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if not client then
				return
			end

			local prev = pending_requests[args.data.client_id]
			if prev then
				client:cancel_request(prev.request_id)
				active_tokens[prev.token] = nil
			end

			local token = "sharpies-" .. vim.uv.hrtime()
			active_tokens[token] = true

			local _, request_id = client:request("workspace/diagnostic", {
				previousResultIds = diagnostics.build_previous_result_ids(args.data.client_id),
				identifier = "WorkspaceDocumentsAndProject",
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

---@param opts? sharpies.Config
function M.setup(opts)
	config.setup(opts)
	vim.lsp.handlers["textDocument/diagnostic"] = function() end
	register_progress_handler()
	register_autocmds()

	vim.keymap.set("n", "<leader>pp", function()
		local clients = vim.lsp.get_clients()
		for _, client in ipairs(clients) do
			if client.name == "easy_dotnet" then
				vim.notify("sharpies: requesting workspace diagnostics")
				local token = "sharpies-" .. vim.uv.hrtime()
				active_tokens[token] = true
				client:request("workspace/diagnostic", {
					previousResultIds = diagnostics.build_previous_result_ids(client.id),
					identifier = "WorkspaceDocumentsAndProject",
					partialResultToken = token,
				}, function(err, result, ctx, _)
					active_tokens[token] = nil
					diagnostics.handle_workspace_result(err, result, ctx, _)
					vim.notify("sharpies: finished workspace diagnostics")
				end)
				return
			end
		end
		vim.notify("sharpies: easy_dotnet client not found", vim.log.levels.WARN)
	end, { noremap = true, silent = true })

	vim.keymap.set("n", "<leader>pd", function()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buf, "sharpies://debug-" .. vim.uv.hrtime())
		vim.bo[buf].filetype = "lua"
		vim.bo[buf].buftype = "nofile"

		local content = vim.split(vim.inspect(all_items), "\n")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)

		vim.cmd("botright split")
		vim.api.nvim_win_set_buf(0, buf)
	end)
end

return M
