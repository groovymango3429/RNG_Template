--!strict
local StarterGui = game:GetService("StarterGui")

local NotificationController = {}

function NotificationController:Show(payload)
    local title = payload.Kind or "Info"
    local text = payload.Message or ""
    local ok = pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = 4,
        })
    end)

    if not ok then
        warn(string.format("[Notification] %s: %s", title, text))
    end
end

return NotificationController
