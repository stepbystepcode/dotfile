-- ~/.config/yazi/plugins/drag-copy.yazi/main.lua

local get_cwd = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

local function entry(_, job)
	local mode = job.args[1] == "move" and "move" or "copy"

	local cwd = get_cwd()
	if not cwd then
		return
	end

	local value, event = ya.input({
		title = (mode == "move" and "Ghostty Move" or "Ghostty Copy") .. " (Drag file here):",
		pos = { "center", w = 50, h = 3 },
	})

	if event ~= 1 then
		return
	end

	local cmd_exec = mode == "move" and "mv" or "cp -r"

	local cmd_str = string.format("%s %s %s", cmd_exec, value, ya.quote(cwd))

	local child, err = Command("sh"):arg("-c"):arg(cmd_str):spawn()

	if not child then
		ya.notify({ title = "Error", content = "Spawn failed: " .. tostring(err), level = "error" })
		return
	end

	local output, err = child:wait()

	if output and output.success then
		ya.notify({
			title = "Success",
			content = (mode == "move" and "Moved" or "Copied") .. " file successfully!",
			level = "info",
			timeout = 2.0,
		})
	else
		ya.notify({
			title = "Failed",
			content = "Operation failed. Check permissions or path.",
			level = "error",
			timeout = 3.0,
		})
	end
end

return { entry = entry }
