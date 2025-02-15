local player_warnings = {}

minetest.register_chatcommand("warn", {
    description = "Warns a player with a reason (requires 'staff' privilege)",
    params = "<player> <reason>",
    privs = { staff = true },
    func = function(name, param)
        local player_name, reason = param:match("^(%S+)%s+(.+)$")
        if player_name and reason then
            if not player_warnings[player_name] then
                player_warnings[player_name] = { count = 0, reasons = {} }
            end
            player_warnings[player_name].count = player_warnings[player_name].count + 1
            table.insert(player_warnings[player_name].reasons, reason)
            minetest.chat_send_player(player_name, core.colorize("#ff0000", "[ECC-WARNINGS] You have been warned for: " .. reason))
            minetest.chat_send_player(name, core.colorize("#64ff00", "[ECC-WARNINGS] You warned " .. player_name .. " with the reason: " .. reason))
            if player_warnings[player_name].count >= 3 then
                local warning_message = "[ECC-WARNINGS] You have been kicked after 3 warnings. The reasons are:"
                for i, r in ipairs(player_warnings[player_name].reasons) do
                    warning_message = warning_message .. "\n" .. i .. ". " .. r
                end
                minetest.chat_send_player(player_name, core.colorize("#ff0000", warning_message))
                minetest.kick_player(player_name, "[ECC-WARNINGS] You have been kicked for receiving 3 warnings.")
                player_warnings[player_name] = nil
            else
                minetest.chat_send_player(player_name, core.colorize("#ff0000", "[ECC-WARNINGS] You now have " .. player_warnings[player_name].count .. " warnings."))
            end
        else
            minetest.chat_send_player(name, "Usage: /warn <player> <reason>")
        end
    end,
})

minetest.register_privilege("staff", {
    description = "Staff privilege for ECC mod commands.",
    give_to_singleplayer = false,
})

local reports = {}
local report_id_counter = 1

local function save_reports()
    local path = minetest.get_worldpath() .. "/reports.txt"
    local file = io.open(path, "w")
    if file then
        file:write(minetest.serialize(reports))
        file:close()
    end
end

local function load_reports()
    local path = minetest.get_worldpath() .. "/reports.txt"
    local file = io.open(path, "r")
    if file then
        local content = file:read("*a")
        reports = minetest.deserialize(content) or {}
        file:close()
    end
end

load_reports()
minetest.register_on_shutdown(save_reports)

minetest.register_chatcommand("report", {
    description = "Submit a report against another player (for cheating or rule-breaking)",
    params = "<username> <reason>",
    func = function(name, param)
        local reported_name, reason = param:match("^(%S+)%s+(.+)$")
        if reported_name and reason then
            local reported_player = minetest.get_player_by_name(reported_name)
            if not reported_player then
                minetest.chat_send_player(name, core.colorize("#ff0000", "[ECC-REPORT] The player " .. reported_name .. " is not online."))
                return
            end
            local reported_uuid = reported_player:get_player_name()
            local report_id = report_id_counter
            reports[report_id] = {
                reporter_name = name,
                reporter_uuid = name,
                reported_name = reported_name,
                reported_uuid = reported_uuid,
                reason = reason,
                claimed_by = nil,
                closed = false,
            }
            report_id_counter = report_id_counter + 1
            minetest.chat_send_player(name, core.colorize("#00ff00", "[ECC-REPORT] Your report has been submitted."))
        else
            minetest.chat_send_player(name, core.colorize("#ff0000", "[ECC-REPORT] Please provide a username and a reason. Usage: /report <username> <reason>"))
        end
    end,
})

local function generate_report_formspec()
    local formspec = "size[8,9]" .. "label[0.5,0.5;Reports]"
    local y_offset = 1.5
    for report_id, report in pairs(reports) do
        if not report.closed then
            local button_label = report.reason
            if report.claimed_by then
                button_label = button_label .. " (Claimed by " .. report.claimed_by .. ")"
            end
            formspec = formspec .. "button[0.5," .. y_offset .. ";7,1;report_" .. report_id .. ";" .. button_label .. "]"
            y_offset = y_offset + 1.5
        end
    end
    return formspec
end

minetest.register_chatcommand("reports", {
    description = "View all submitted reports (requires 'staff' privilege)",
    privs = { staff = true },
    func = function(name)
        if next(reports) == nil then
            minetest.chat_send_player(name, core.colorize("#ff0000", "[ECC-REPORT] No reports have been submitted yet."))
        else
            minetest.show_formspec(name, "report_system:reports", generate_report_formspec())
        end
    end,
})

minetest.register_on_player_receive_fields(function(player, formname, fields)
    local pname = player:get_player_name()
    if formname == "report_system:reports" then
        for field, _ in pairs(fields) do
            if field:sub(1, 7) == "report_" then
                local report_id = tonumber(field:sub(8))
                if report_id and reports[report_id] then
                    local report = reports[report_id]
                    local claimed_by = report.claimed_by or "Not claimed"
                    local status = report.closed and "Closed" or "Open"
                    local formspec = "size[8,9]"
                    formspec = formspec .. "label[0.5,0.5;Report ID: " .. report_id .. "]"
                    formspec = formspec .. "label[0.5,1.0;Reporter: " .. report.reporter_name .. "]"
                    formspec = formspec .. "label[0.5,1.5;Reported: " .. report.reported_name .. "]"
                    formspec = formspec .. "label[0.5,2.0;Reason: " .. report.reason .. "]"
                    formspec = formspec .. "label[0.5,2.5;Claimed by: " .. claimed_by .. "]"
                    formspec = formspec .. "label[0.5,3.0;Status: " .. status .. "]"
                    formspec = formspec .. "button[0.5,4.0;3,1;claim_" .. report_id .. ";Claim]"
                    formspec = formspec .. "button[4.5,4.0;3,1;close_" .. report_id .. ";Close]"
                    minetest.show_formspec(pname, "report_system:report_details_" .. report_id, formspec)
                end
            end
        end
    end
    if formname:sub(1,29) == "report_system:report_details_" then
        local report_id = tonumber(formname:sub(30))
        if report_id and reports[report_id] then
            local report = reports[report_id]
            if fields["claim_" .. report_id] then
                report.claimed_by = pname
                minetest.chat_send_player(pname, core.colorize("#00ff00", "[ECC-REPORT] You have claimed report " .. report_id))
            end
            if fields["close_" .. report_id] then
                report.closed = true
                minetest.chat_send_player(report.reporter_name, core.colorize("#00ff00", "[ECC-REPORT] Your report " .. report_id .. " has been dealt with."))
                minetest.chat_send_player(pname, core.colorize("#00ff00", "[ECC-REPORT] You have closed report " .. report_id))
            end
            minetest.show_formspec(pname, "report_system:reports", generate_report_formspec())
        end
    end
end)
