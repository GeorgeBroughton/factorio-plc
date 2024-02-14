require "util"
require "intellisense"

local M = {}
local structure = require "structure"
local program = require "program"

function M.on_init()
	global.gui = global.gui or {}
end

---comment
---@param event EventData.on_gui_opened
function M.on_gui_opened(event)
	-- Replace constant-combinator gui with scanner gui
	local entity = event.entity
	if event.gui_type == defines.gui_type.entity and entity and entity.valid and entity.name == "plc-unit" then
		local player = game.get_player(event.player_index)
		if player ~= nil then
			local gui = player.gui.screen
			local struct = structure.get_structure(entity.unit_number)
			local running = struct.data.running
			-- Destroy any old versions
			if gui["signal-controller-outer-frame"] then
				gui["signal-controller-outer-frame"].destroy()
			end
			-- create main panel
			local main_frame = gui.add {
				type = "frame",
				name = "signal-controller-outer-frame",
				direction = "vertical",
			}
			main_frame.tags = {["unit_number"] = entity.unit_number}
			main_frame.auto_center = true
			-- create title bar with dragger
			local titlebar = main_frame.add {
				type = "flow"
			}
			titlebar.drag_target = main_frame
			titlebar.add {
				type = "label",
				style = "frame_title",
				caption = entity.localised_name,
				ignored_by_interaction = true,
			}
			local filler = titlebar.add {
				type = "empty-widget",
				style = "draggable_space",
				ignored_by_interaction = true,
			}
			filler.style.height = 24
			filler.style.horizontally_stretchable = true
			titlebar.add {
				type = "sprite-button",
				name = "signal-controller-close",
				style = "frame_action_button",
				sprite = "utility/close_white",
				hovered_sprite = "utility/close_black",
				clicked_sprite = "utility/close_black",
				tooltip = { "gui.close-instruction" },
			}
			local run_frame = main_frame.add{ type = "flow", name = "signal-controller-run-frame" }
			run_frame.style.vertical_align = "center"

			local run_stop_sprite = running and "plc-pause-button" or "plc-play-button"
			local run_button = run_frame.add {
				type = "sprite-button",
				name = "signal-controller-program-run",
		--		style = "frame_action_button",
				sprite = run_stop_sprite.."-white",
				hovered_sprite = run_stop_sprite.."-black",
				clicked_sprite = run_stop_sprite.."-black",
				tooltip = running and "Stop program execution" or "Run program execution",
				tags = {["unit_number"] = entity.unit_number},
			}
			local run_label = run_frame.add({
				type = "label",
				name = "signal-controller-program-run-label",
				caption = running and "[ Program Running ]" or "[ Program Stopped ]",
			})
			local sep1 = main_frame.add({
				type = "line",
				direction = "horizontal",
			})
			-- add tabbed pane
			local tabbed_pane = main_frame.add { type = "tabbed-pane", name = "signal-controller-tabbed-pane" }

			-- add the program panel
			local program_tab = add_tab(tabbed_pane, "Program", programPage, struct)
			-- add the variables panel
			local variables_tab = add_tab(tabbed_pane, "Variables", variablePage, struct)
			-- add the inputs panel
			local inputs_tab = add_tab(tabbed_pane, "Inputs", inputPage, struct)
			-- add the outputs panel
			local outputs_tab = add_tab(tabbed_pane, "Outputs", outputPage, struct)

			-- make the gui active
			player.opened = main_frame
		end
	end
end

function add_tab(tab_pane, name, content_func, struct)
	local tab = tab_pane.add {
		type = "tab",
		caption = name,
	}
	local pane = tab_pane.add {
		type = "scroll-pane",
		direction = "vertical",
		horizontal_scroll_policy = "never",
		vertical_scroll_policy = "always",
		name = "signal-controller-"..name:lower().."-pane",
	}
	pane.style.maximal_height = 500
	local frame = pane.add {
		type = "frame",
		style = "entity_frame",
		direction = "vertical",
	}
	frame.style.vertically_stretchable = true
	content_func(frame, struct)
	tab_pane.add_tab(tab, pane)
	return tab
end

---comment
---@param parent LuaGuiElement
---@param line integer
---@param entry structure.program.variable_data|structure.program.inputoutput_data
---@param enabled any
---@param direction any
---@param struct any
---@return unknown
function add_named_signal_row(parent, line, entry, enabled, direction, struct)
	local name = "signal-controller-" .. direction
	local page_flow = parent.add {
		type = "flow",
	}
	page_flow.style.vertical_align = "center"
	page_flow.style.horizontally_stretchable = true
	local label = page_flow.add {
		type = "label",
		caption = "Slot "..line..":",
	}
	local textbox = page_flow.add{
		text = entry.name,
		type = "textfield",
		tooltip = { "plc_tooltip."..direction.."_variable_select" },
		tags = {["line"] = line, ["unit_number"] = struct.entities.main.unit_number},
		name = name .. "-name-" .. line,
	}
	textbox.enabled = enabled
	if direction ~= "variable" then
		local button = page_flow.add{
			type = "choose-elem-button",
			style = "plc-unit-slot",
			tags = {["line"] = line, ["unit_number"] = struct.entities.main.unit_number},
			elem_type = "signal",
			name = name .. "-signal-" .. line,
		}
		button.elem_value = entry.signal
		button.enabled = enabled
	end
	if direction == "input" then
		local wbutton = page_flow.add{
			type = "switch",
			tooltip = "Wire to take signal from",
			tags = {["line"] = line, ["unit_number"] = struct.entities.main.unit_number},
			name = name .. "-wire-" .. line,
		}
		wbutton.left_label_caption = "Green"
		wbutton.right_label_caption = "Red"
		wbutton.allow_none_state = true
		wbutton.switch_state = entry.wire or "none"
		wbutton.enabled = enabled
	end
	return page_flow
end
---GUI Close event
---@param event EventData.on_gui_closed
function M.on_gui_closed(event)
	if event.gui_type == defines.gui_type.custom then
		if event and event.element and event.element.name then
			if event.element.name == "signal-controller-outer-frame" then
				event.element.destroy()
			end
		end
	end
end

---Create program selection page
---@param frame LuaGuiElement
---@param struct structure_table
function programPage(frame, struct)
	local cmdList = {}
	for ind, command in pairs(program.commandList) do
		cmdList[ind] = command.disp
	end
	local running = struct.data.running
	-- get number of lines from structure
	local count = struct.program.program_count
	-- get the program data from structure
	local prog = struct.program.program_data
	-- process the program
	for line = 1, count do
		local line_frame = frame.add{ type = "flow", }
		line_frame.style.vertical_align = "center"
		-- get the line or default it
		prog[line] = prog[line] or { cmd = 1, params = {} }
		local code = prog[line]
		local command = program.commandList[code.command]
		-- display the line
		-- action buttons
		local del_button = line_frame.add({
			type = "sprite-button",
			name = "signal-controller-program-delete-" .. line,
			enabled = not running,
			sprite = "plc-trash-button-white",
			hovered_sprite = "plc-trash-button-black",
			clicked_sprite = "plc-trash-button-black",
			tooltip = { "plc_tooltip.delete_line" },
			tags = {["line"] = line, ["unit_number"] = struct.entities.main.unit_number},
		})
		local up_button = line_frame.add({
			type = "sprite-button",
			name = "signal-controller-program-up-" .. line,
			enabled = line ~= 1 and not running,
			sprite = "plc-up-button-white",
			hovered_sprite = "plc-up-button-black",
			clicked_sprite = "plc-up-button-black",
			tooltip = { "plc_tooltip.move_line_up" },
			tags = {["line"] = line, ["unit_number"] = struct.entities.main.unit_number},
		})
		local down_button = line_frame.add({
			type = "sprite-button",
			name = "signal-controller-program-down-" .. line,
			enabled = line ~= count and not running,
			sprite = "plc-down-button-white",
			hovered_sprite = "plc-down-button-black",
			clicked_sprite = "plc-down-button-black",
			tooltip = { "plc_tooltip.move_line_down" },
			tags = {["line"] = line, ["unit_number"] = struct.entities.main.unit_number},
		})
		-- command info
		local cmd_dropdown = line_frame.add({
			type = "drop-down",
			name = "signal-controller-command-" .. line,
			style = "plc_dropdown",
			tooltip = { "plc_command_tooltip." .. (command.disp) },
			items = cmdList,
			selected_index = code.command,
			enabled = not running,
			tags = {["line"] = line, ["unit_number"] = struct.entities.main.unit_number},
		})
		local cmd_param1 = line_frame.add({
			type = "textfield",
			name = "signal-controller-param1-" .. line,
			style = "plc_textfield",
			tooltip = { "plc_tooltip.parameter1" },
			text = code.parameter1 and code.parameter1 or "",
			enabled = not running and (command.params > 0),
			tags = {["line"] = line, ["unit_number"] = struct.entities.main.unit_number},
		})
		local cmd_param2 = line_frame.add({
			type = "textfield",
			name = "signal-controller-param2-" .. line,
			style = "plc_textfield",
			tooltip = { "plc_tooltip.parameter2" },
			text = code.parameter2 and code.parameter2 or "",
			enabled = not running and (command.params > 1),
			tags = {["line"] = line, ["unit_number"] = struct.entities.main.unit_number},
		})
		local cmd_param3 = line_frame.add({
			type = "textfield",
			name = "signal-controller-param3-" .. line,
			style = "plc_textfield",
			tooltip = { "plc_tooltip.parameter3" },
			text = code.parameter3 and code.parameter3 or "",
			enabled = not running and (command.params > 2),
			tags = {["line"] = line, ["unit_number"] = struct.entities.main.unit_number},
		})
	end
end

---Create input selection page
---@param frame LuaGuiElement
---@param struct structure_table
function inputPage(frame, struct)
	local count = struct.program.input_count
	for line = 1, count do
		local entry = struct.program.input_data[line]
		add_named_signal_row(frame, line, entry, (struct.data.running == false), "input", struct)
	end
end

---Create output selection page
---@param frame LuaGuiElement
---@param struct structure_table
function outputPage(frame, struct)
	local count = struct.program.output_count
	for line = 1, count do
		local entry = struct.program.output_data[line]
		add_named_signal_row(frame, line, entry, (struct.data.running == false), "output", struct)
	end
end

---Create variables selection page
---@param frame LuaGuiElement
---@param struct structure_table
function variablePage(frame, struct)
	local count = struct.program.variable_count
	for line = 1, count do
		local entry = struct.program.variable_data[line]
		add_named_signal_row(frame, line, entry, (struct.data.running == false), "variable", struct)
	end
end

--- Updates text and such from the program data
---@param gui_program_row LuaGuiElement
---@param code structure.program.program_data
local function update_program_line(gui_program_row, code, enabled)
	local command = program.commandList[code.command]
	gui_program_row.children[1].enabled = enabled -- trash
	gui_program_row.children[2].enabled = enabled -- up
	gui_program_row.children[3].enabled = enabled -- down
	gui_program_row.children[4].enabled = enabled -- command
	gui_program_row.children[4].tooltip = { "plc_command_tooltip." .. (command.disp) }
	gui_program_row.children[4].selected_index = code.command
	gui_program_row.children[5].enabled = enabled and (command.params > 0) -- param 1
	gui_program_row.children[5].text = code.parameter1 and code.parameter1 or ""
	gui_program_row.children[6].enabled = enabled and (command.params > 1)-- param 2
	gui_program_row.children[6].text = code.parameter2 and code.parameter2 or ""
	gui_program_row.children[7].enabled = enabled and (command.params > 2)-- param 3
	gui_program_row.children[7].text = code.parameter3 and code.parameter3 or ""
end

-- something was clicked
---comment
---@param event EventData.on_gui_click
function M.on_gui_click(event)
	if not event or not event.element or not event.element.name or event.element.name == "" then
		return
	end
	local element = event.element
	local etype = element.type
	if etype == "choose-elem-button" or
		etype == "drop-down" or
		etype == "textfield" then
		return
	end
	-- Close button / hotkeys
	if element.name == "signal-controller-close" then
		element.parent.parent.destroy()
		return
	end
	local player = game.players[event.player_index]
	if not player.gui.screen["signal-controller-outer-frame"] then 
		return
	end
	local gui = player.gui.screen["signal-controller-outer-frame"]
	local unit_number = tonumber(element.tags["unit_number"])
	if not unit_number then
		return
	end
	local struct = structure.get_structure(unit_number)
	-- run/stop button
	if element.name == "signal-controller-program-run" and struct ~= nil then
		-- Set the updated run/stop info
		local run_stop_button = gui["signal-controller-run-frame"]["signal-controller-program-run"]
		local run_stop_label = gui["signal-controller-run-frame"]["signal-controller-program-run-label"]
		if struct.data.running then
			struct.data.running = false
			run_stop_button.sprite = "plc-play-button-white"
			run_stop_button.hovered_sprite = "plc-play-button-black"
			run_stop_button.clicked_sprite = "plc-play-button-black"
			run_stop_label.caption = "[ Program Stopped ]"
		else
			struct.data.running = true
			run_stop_button.sprite = "plc-pause-button-white"
			run_stop_button.hovered_sprite = "plc-pause-button-black"
			run_stop_button.clicked_sprite = "plc-pause-button-black"
			run_stop_label.caption = "[ Program Running ]"
		end
		local enabled = not struct.data.running
		-- Update enabled setting for other things
		local input_frame = gui["signal-controller-tabbed-pane"]["signal-controller-inputs-pane"].children[1]
		for i = 1, struct.program.input_count do
			input_frame.children[i].children[2].enabled = enabled -- name
			input_frame.children[i].children[3].enabled = enabled -- signal
			input_frame.children[i].children[4].enabled = enabled -- wire
		end
		local output_frame = gui["signal-controller-tabbed-pane"]["signal-controller-outputs-pane"].children[1]
		for i = 1, struct.program.output_count do
			output_frame.children[i].children[2].enabled = enabled -- name
			output_frame.children[i].children[3].enabled = enabled -- signal
		end
		local variable_frame = gui["signal-controller-tabbed-pane"]["signal-controller-variables-pane"].children[1]
		for i = 1, struct.program.variable_count do
			variable_frame.children[i].children[2].enabled = enabled -- name
		end
		local program_frame = gui["signal-controller-tabbed-pane"]["signal-controller-program-pane"].children[1]
		for i = 1, struct.program.program_count do
			local cmd_ind = program_frame.children[i].children[4].selected_index
			local command = program.commandList[cmd_ind]
			program_frame.children[i].children[1].enabled = enabled -- trash
			program_frame.children[i].children[2].enabled = enabled -- up
			program_frame.children[i].children[3].enabled = enabled -- down
			program_frame.children[i].children[4].enabled = enabled -- command
			program_frame.children[i].children[5].enabled = enabled and (command.params > 0) -- param 1
			program_frame.children[i].children[6].enabled = enabled and (command.params > 1)-- param 2
			program_frame.children[i].children[7].enabled = enabled and (command.params > 2)-- param 3
		end
		return
	end
	-- Handle button events
	-- get the element details
	local command, line = string.match(event.element.name, "^signal%-controller%-program%-(.+)%-(%d+)$")
	-- Check if the string matches
	line = tonumber(line)
	if command ~= nil and line ~= nil and struct ~= nil then
		local program_frame = gui["signal-controller-tabbed-pane"]["signal-controller-program-pane"].children[1]
		local enabled = not struct.data.running
		if command == "delete" then
			-- empty the program line
			struct.program.program_data[line] = { command = 1, parameter1 = "", parameter2 = "", parameter3 = "", }
			-- update the gui line
			update_program_line(program_frame.children[line], struct.program.program_data[line], enabled)
		elseif command == "down" and line < struct.program.program_count then
			-- swap this line with the one below it
			local tmp1 = struct.program.program_data[line]
			local tmp2 = struct.program.program_data[line + 1]
			struct.program.program_data[line] = tmp2
			struct.program.program_data[line + 1] = tmp1
			-- update both lines
			update_program_line(program_frame.children[line], struct.program.program_data[line], enabled)
			update_program_line(program_frame.children[line + 1], struct.program.program_data[line + 1], enabled)
		elseif command == "up" and line > 1 then
			-- swap this line with the one above it
			local tmp1 = struct.program.program_data[line]
			local tmp2 = struct.program.program_data[line - 1]
			struct.program.program_data[line] = tmp2
			struct.program.program_data[line - 1] = tmp1
			-- update both lines
			update_program_line(program_frame.children[line], struct.program.program_data[line], enabled)
			update_program_line(program_frame.children[line - 1], struct.program.program_data[line - 1], enabled)
		end
		return
	end
	-- get the element details
	local name, number = string.match(event.element.name, "^signal%-controller%-(.+)%-(%d+)$")
	-- Check if the string matches
	if name and number and struct ~= nil then
		number = tonumber(number)
		if name == "input-wire" then
			struct.program.input_data[number].wire = element.switch_state
		elseif name == "output-wire" then
			struct.program.output_data[number].wire = element.switch_state
		end
		return
	end
	-- xyz handling
	player.print("Unhandled event onClick - element.name = "..element.name)
	player.print("element.type = "..element.type)
end
-- something on the gui changed
---comment
---@param event EventData.on_gui_elem_changed
function M.on_gui_changed(event)
	local player = game.players[event.player_index]
	local element = event.element
	-- get the element details
	local name, number = string.match(event.element.name, "^signal%-controller%-(.+)%-(%d+)$")
	-- Check if the string matches
	if not name or not number or not element.tags or not element.tags["unit_number"] then
		return
	end
	local gui = player.gui.screen["signal-controller-outer-frame"]
	local program_frame = gui["signal-controller-tabbed-pane"]["signal-controller-program-pane"].children[1]

	-- grab the struct info
	local unit_number = tonumber(element.tags["unit_number"])
	if not unit_number then
		return
	end
	local struct = structure.get_structure(unit_number)
	if not struct then
		return
	end
	number = tonumber(number)
	-- menu tab handling
	if name == "input-name" then
		struct.program.input_data[number].name = element.text
	elseif name == "input-signal" then
		struct.program.input_data[number].signal = element.elem_value
	elseif name == "output-name" then
		struct.program.output_data[number].name = element.text
	elseif name == "output-signal" then
		struct.program.output_data[number].signal = element.elem_value
	elseif name == "variable-name" then
		struct.program.variable_data[number].name = element.text
	elseif name == "param1" then
		struct.program.program_data[number].parameter1 = element.text
	elseif name == "param2" then
		struct.program.program_data[number].parameter2 = element.text
	elseif name == "param3" then
		struct.program.program_data[number].parameter3 = element.text
	elseif name == "command" then
		local new_value = element.selected_index
		struct.program.program_data[number].command = new_value
		local command = program.commandList[new_value or 1]
		local row = program_frame.children[number]
		row.children[4].tooltip = { "plc_command_tooltip." .. (command.disp) }
		row.children[5].enabled = (command.params > 0) -- param 1
		row.children[6].enabled = (command.params > 1) -- param 2
		row.children[7].enabled = (command.params > 2) -- param 3
	else
		player.print("Unhandled event onGuiChanged - element.name = "..element.name)
	end
end

-- return as table
return M
