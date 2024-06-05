local Drawer = require("Drawer")
local Button = {}

Button._buttons = {}

Button.addButton = function (text, act, x, y, w, h, bgColor, fgColor)
    local button = {
        text = text,
        x = x,
        y = y,
        w = w,
        h = h,
        act = act,
        bgColor = bgColor,
        fgColor = fgColor
    }
    table.insert(Button._buttons, button)
end

Button.draw = function ()
    for i, button in ipairs(Button._buttons) do
        local prevBgColor, prevFgColor
        if button.bgColor then
            prevBgColor = Drawer.monitor.getBackgroundColor()
            Drawer.monitor.setBackgroundColor(button.bgColor)
        end
        if button.fgColor then
            prevFgColor = Drawer.monitor.getTextColor()
            Drawer.monitor.setTextColor(button.fgColor)
        end
        if button.h > 1 then
            local half = button.h/2
            for _y = -math.floor(half) + 1, math.ceil(half) do
                local y = button.y + _y
                Drawer.monitor.setCursorPos(button.x, y)
                Drawer.monitor.write(string.rep(" ", button.w))
            end
        end


        local text = button.text
        text = string.rep(" ", math.floor((button.w - string.len(text)) / 2))..text..string.rep(" ", math.ceil((button.w - string.len(text)) / 2))
        Drawer.writeCentered(text, button.x, button.y, button.w, button.h)
        if button.bgColor then
            Drawer.monitor.setBackgroundColor(prevBgColor)
        end
        if button.fgColor then
            Drawer.monitor.setTextColor(prevFgColor)
        end
    end
end

Button.clear = function ()
    Button._buttons = {}
end

Button._handler = function ()
    while true do
        local event, side, x, y = os.pullEvent("monitor_touch")
        for i, button in ipairs(Button._buttons) do
            if x >= button.x and x <= button.x + button.w - 1 then
                local half = button.h/2
                -- print(button.h, half, button.y, y, button.y + (-math.floor(half) + 1), button.y + math.ceil(half))
                local y_match = false
                if button.h == 1 then y_match = y == button.y
                else y_match = y >= button.y + (-math.floor(half) + 1) and y <= button.y + math.ceil(half) end

                if y_match then button.act() end
            end
        end
      end
end

return Button