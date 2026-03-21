local config = require("roslyn-workspace-diagnostics.config")

local M = {}

---@param callback fun(client_id: integer)
function M.onWorkspaceComplete(callback)
	vim.api.nvim_create_autocmd("LspAttach", {
		callback = function(args)
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if not client or not vim.tbl_contains(config.options.roslyn_alias, client.name) then
				return
			end

			if client._roslyn_workspace_patched then
				return
			end
			client._roslyn_workspace_patched = true

			local pending = 0
			local orig_request = client.request
			client.request = function(self, method, params, handler, ...)
				if method == "workspace/diagnostic" then
					pending = pending + 1
					local ok, request_id = orig_request(self, method, params, function(err, result, ctx)
						if handler then
							handler(err, result, ctx)
						end
						pending = pending - 1
						if pending == 0 then
							callback(client.id)
						end
					end, ...)
					if not ok then
						pending = pending - 1
					end
					return ok, request_id
				end
				return orig_request(self, method, params, handler, ...)
			end

			-- Reset pending on new refresh cycle to clear stale counts
			-- from requests silently cancelled via RequestCancelled
			local orig_provider_foreach = client._provider_foreach
			client._provider_foreach = function(self2, method, ...)
				if method == "workspace/diagnostic" then
					pending = 0
				end
				return orig_provider_foreach(self2, method, ...)
			end
		end,
	})
end

return M
