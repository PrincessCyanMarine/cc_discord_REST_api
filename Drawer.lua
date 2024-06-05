local Drawer = {}

Drawer.monitor = nil

Drawer.writeCentered = function (text, x, y, width, height, _monitor, bgColor, fgColor)
    local prevBgColor = Drawer.monitor.getBackgroundColor()
    local prevFgColor = Drawer.monitor.getTextColor()
    if not bgColor then
        bgColor = prevBgColor
    end
    if not fgColor then
        fgColor = prevFgColor
    end
    Drawer.monitor.setBackgroundColor(bgColor)
    Drawer.monitor.setTextColor(fgColor)
    if not _monitor then
        _monitor = Drawer.monitor
    end
    local text_width = string.len(text)
    x = x + width / 2 - text_width / 2
    y = y + height / 2
    _monitor.setCursorPos(x, y)
    _monitor.write(text)
    Drawer.monitor.setBackgroundColor(prevBgColor)
    Drawer.monitor.setTextColor(prevFgColor)
end

return Drawer