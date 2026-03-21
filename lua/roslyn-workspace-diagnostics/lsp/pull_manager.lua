local M = {}

---@type table<integer, uv.uv_timer_t>
local client_timers = {}

function M._stop_pulling(client_id)
	if client_timers[client_id] then
		client_timers[client_id]:stop()
		client_timers[client_id]:close()
		client_timers[client_id] = nil
	end
end

function M._schedule_next_pull(client_id)
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
			vim.lsp.buf.workspace_diagnostics({ client_id = client_id })
		end)
	)
end

return M
