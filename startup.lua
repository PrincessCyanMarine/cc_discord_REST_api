local json = require("lib/json")
-- local sha = require("lib/sha")

function getKey(key)
    local file = fs.open(key..".pem", "r")
    if not file then error("No key found") end
    local res = file.readAll()
    file.close()
    return res
end

-- local private_key = getKey("priv")
-- local public_key = getKey("pub")
-- local server_key = nil

local Drawer = require("Drawer")
local Button = require("Button")
local chatbox = peripheral.find("chatBox")
local monitor = peripheral.find("monitor")
Drawer.monitor = monitor

if not chatbox then
    error("No chatbox found")
end

if not monitor then
    error("No monitor found")
end
monitor.setTextScale(0.5)
monitor.setBackgroundColor(colors.black)
monitor.setTextColor(colors.white)

local ws = http.websocket("ws://localhost:4000")
if not ws then
    error("Failed to connect to websocket")
end
-- print(ws)
-- ws.send(textutils.serializeJSON({ type="KEY", key=public_key }))

local AUTH_STATE = {
    NOT_AUTHENTICATED = 0,
    AUTHENTICATING = 1,
    AUTHENTICATED = 2
}

local auth_state = AUTH_STATE.NOT_AUTHENTICATED
local token = nil

local guilds = nil
local channels = nil
local messages = nil
local bots = nil

local selected_guild = nil
local selected_channel = nil
local selected_bot = nil
local being_edited = nil
local editing_bot = nil

local scroll = 0
local fetch_queue = {}

function saveLocally(key, value)
    local file = fs.open("data/"..key, "w")
    file.write(value)
    file.close()
end

function loadLocally(key)
    local file = fs.open("data/"..key, "r")
    if not file then
        return nil
    end
    local value = file.readAll()
    file.close()
    return value
end

function onMessage()
    while true do
        os.sleep(0.1)
        local message = ws.receive()
        -- print(message)
        if not message then
            print("Empty message received")
        else
            local data = textutils.unserializeJSON(message, {parse_empty_array = false})
            if not data then
                -- print("Failed to parse JSON")
                return
            end
            -- print(data.type)
            if data.type == "KEY" then
                server_key = data.key
            elseif data.type == "ERROR" then
                error("Server Error: "..data.message)
            elseif data.type == "AUTH_URL" then
                chatbox.sendFormattedMessage(
                    textutils.serialiseJSON({
                        {text = "Please authenticate "}, 
                        {
                            text = "here",
                            underlined = true,
                            color = "aqua",
                            clickEvent = {
                                action = "open_url",
                                value = data.url
                            }
                        }
                    })    
                )
                token = read()
                saveLocally("token", textutils.serialiseJSON({token = token, expires_at = os.epoch("utc") + 3600000}))
                auth_state = AUTH_STATE.AUTHENTICATED
            elseif data.type == "MESSAGE" then
                addMessage(data.message)
            elseif data.type == "MESSAGE_DELETED" then
                for i, message in ipairs(messages) do
                    if message.id == data.messageId then
                        table.remove(messages, i)
                        break
                    end
                end
            elseif data.type == "MESSAGE_UPDATED" then
                for i, message in ipairs(messages) do
                    if message.id == data.message.id then
                        messages[i] = data.message
                        break
                    end
                end
            end
        end
    end
end

function setChannel(_ch)
    if _ch ~= nil and selected_guild and _ch.guildId == selected_guild.id and _ch.channels and #_ch.channels > 0 then
        channels = _ch.channels
        function sel()
            local _, channel = pairs(channels)(channels)
            selectChannel(channel)
        end

        if not selected_channel then sel()
        else
            for key, value in pairs(channels) do
                if value.id == selected_channel.id then
                    return
                end
                sel()
            end
        end
    end
end

function addMessage(msg)
    if messages then
        table.insert(messages, 1, msg)
    end
end

function deleteMessage(pos)
    local res = http.post("http://localhost:4000/message/delete",
        textutils.serialiseJSON({
            token = token,
            channelId = selected_channel.id,
            messageId=messages[pos].id,
            botName=bots[messages[pos].author.id]
        }),
        {["Content-Type"]="application/json"}
    ).readAll()
end

function getMessages() 
    print("Getting messages")
    fetch(function ()
        if not selected_channel then return end
        local res = http.post("http://localhost:4000/messages/",
            textutils.serialiseJSON({token = token, channelId = selected_channel.id}),
            {["Content-Type"]="application/json"}
        ).readAll()
        -- print(res)
        _messages = textutils.unserializeJSON(res)
        if not _messages or not selected_channel or _messages.channelId ~= selected_channel.id then return end
        messages = _messages.messages
        -- local message = { type="SELECT_CHANNEL", channelId=selected_channel.id, token=token }
        -- local sign = sha.hmac(sha.sha256, private_key, textutils.serializeJSON(message))
        -- ws.send(textutils.serializeJSON({message=message--[[ , sign=sign ]]}))
        ws.send(textutils.serializeJSON({ type="SELECT_CHANNEL", channelId=selected_channel.id, token=token }))
    end)
end

function getChannels()
    fetch(function ()
        if not selected_guild then return nil end
        local saved_channels = loadLocally("channels/"..selected_guild.id)
        -- print("saved_channels", saved_channels)
        if saved_channels then
            setChannel(textutils.unserializeJSON(saved_channels))
        end
        local _saved_channels = http.post(
            "http://localhost:4000/channels/",
            textutils.serialiseJSON({token = token, guildId = selected_guild.id}),
            {["Content-Type"]="application/json"}
        )
        if not _saved_channels then return end
        _saved_channels = _saved_channels.readAll()
        if _saved_channels == saved_channels then return end
        saved_channels = _saved_channels
        saveLocally("channels/"..selected_guild.id, saved_channels)
        setChannel(textutils.unserializeJSON(saved_channels))
    end)
end

function includes(item, array)
    if not array then return false end
    for i, v in ipairs(array) do
        if v == item then
            return true
        end
    end
    return false

end

function selectChannel(_channel)
    if _channel and selected_channel and _channel.id == selected_channel.id then return end
    scroll = 0
    selected_channel = _channel
    messages = nil
    bots = _channel.bots
    if not selected_channel then
        selected_bot = nil
        return
    end
    getMessages()
    being_edited = nil
    editing_bot = nil
    if not includes(selected_bot, bots) then selected_bot = nil end
end

function selectGuild(guild)
    selected_guild = guild
    -- print(guild.name)
    selected_channel = nil
    selected_bot = nil
    channels = nil
    bots = nil
    messages = nil
    scroll = 0
    getChannels()
end

function getGuilds()
    -- print("Getting guilds...")
    fetch(function ()
        local saved_guilds = loadLocally("guilds")
        if not saved_guilds then
            saved_guilds = http.post(
                "http://localhost:4000/guilds/",
                textutils.serialiseJSON({token = token}),
                {["Content-Type"]="application/json"}
            ).readAll()
            saveLocally("guilds", saved_guilds)
        end
        guilds = textutils.unserializeJSON(saved_guilds)
        
        local _, guild = pairs(guilds)(guilds)
        selectGuild(guild)
    end)
end


function getSavedToken()
    local saved_token = loadLocally("token")
    if saved_token then
        saved_token = textutils.unserializeJSON(saved_token)
        if saved_token.expires_at >= os.epoch("utc") then           
            return saved_token.token
        end
    end
    return nil
end



local dots = 0
function tickDots()
    while true do
        dots = (dots + 1) % 4
        os.sleep(0.5)
    end
end

function dottedString(str)
    return str..(string.rep(".", dots)..(string.rep(" ", 3-dots)))
end

function showGuilds(_guilds)
    monitor.setTextScale(1)
    local width, height = monitor.getSize()
    local i = 1
    for id, guild in pairs(_guilds) do
        monitor.setCursorPos(1, i)
        local initials = string.sub(guild.name, 1, 1)
        for word in string.gmatch(guild.name, " (%a)") do
            initials = initials..word
        end
        if string.len(initials) > 5 then
            initials = string.sub(initials, 1, 5)
        end
        Button.addButton(initials, function ()
            -- print("Selected guild "..guild.name)
            selectGuild(guild)
        end, 1, i, 7, 1, selected_guild and selected_guild.id == guild.id and colors.lightGray or colors.green, colors.white)
        i = i + 1
    end
end 

function selectBot(_bot)
    selected_bot = _bot
end

function showBots(_bots)
    monitor.setTextScale(1)
    local width, height = monitor.getSize()
    local i = 1
    for id, bot in pairs(_bots) do
        if not selected_bot then
            selected_bot = bot
        end
        monitor.setCursorPos(1, i)
        Button.addButton(string.sub(bot, 1, 9), function ()
            selectBot(bot)
        end, 71, i, 11, 1, selected_bot == bot and colors.lightGray or colors.green, colors.white)
        i = i + 1
    end
end

function showChannels(_channels)
    monitor.setTextScale(1)
    local width, height = monitor.getSize()
    local i = 1
    -- print("_channels", _channels)
    for id, channel in pairs(_channels) do
        monitor.setCursorPos(1, i)
        -- print("channel", channel)
        local text = string.sub(channel.name, 1, 10)
        Button.addButton(text, function ()
            -- print("Selected channel "..channel.name)
            selectChannel(channel)
        end, 8, i, 12, 1, selected_channel and selected_channel.id == channel.id and colors.lightGray or colors.yellow, colors.black)
        i = i + 1
    end

end


function isBotControllable(author_id)
    for id, bot in pairs(bots) do
        if id == author_id then
            return true
        end
    end
    return false
end


function showMessages(_messages)
    monitor.setTextScale(1)
    local width, height = monitor.getSize()
    -- monitor.setCursorPos(1, height)
    -- monitor.write(#messages)
    local _m = {}
    for id, message in pairs(_messages) do _m[#_m + 1] = message end
    -- for i, m in ipairs(_m) do
    --     print(i, m.content)
    -- end
    local shown = 0
    local y = height
    for i = 1 + scroll, #_m, 1 do
        local message = _m[i]
        if message ~= nil then 
            monitor.setTextColor(colors.white)
            if message.id == being_edited then
                monitor.setTextColor(colors.lightBlue)
            end

            local content = message.content
            if #message.attachments >= 1 then
                content = content..(
                    content == "" and "" or " "
                ).."[ATTACHMENT] ".."("..#message.attachments..")"
            end
            if content == "" then
                content = "[EMPTY MESSAGE]"
            end
            y = y - 1
            if y < 1 then break end
            while string.len(content) > 0 do
                local _c = string.sub(content, #content - 39)
                monitor.setCursorPos(23, y)
                monitor.write(_c)
                content = string.sub(content, 1, #content - 40)
                if string.len(content) > 40 then
                    y = y - 1
                    if y < 1 then break end
                end
            end
            y = y - 1
            if y < 1 then break end
            local username = message.author.username
            if message.author.bot then
                username = username.." [BOT]"
                if isBotControllable(message.author.id) then
                    Button.addButton("[EDIT]", function ()
                        if not bots then return end
                        if being_edited == message.id then
                            being_edited = nil
                            editing_bot = nil
                        else
                            being_edited = message.id
                            editing_bot = bots[message.author.id]
                        end
                    end, 22 + string.len(username), y, 6, 1, nil, message.id == being_edited and colors.lightBlue or colors.red)
                    Button.addButton("[DELETE]", function ()
                        -- print("DELETE "..message.author.id)
                        deleteMessage(i)
                    end, 29 + string.len(username), y, 8, 1, nil, colors.red)
                end
            end
            monitor.setCursorPos(21, y)
            monitor.write(username)
            shown = shown + 1
            y = y - 1
            if y < 1 then break end
        end
    end
    monitor.setTextColor(colors.white)

    local max = #_m - shown
    if scroll < max then
        -- Drawer.writeCentered(scroll.."/"..max, 65, 4, 5, 3, nil, nil, colors.blue)
        Button.addButton("^", function ()
            scroll = scroll + 1
            if scroll > max then
                scroll = max
            end
        end, 65, 1, 5, 3, colors.blue, colors.white)
    end
    if scroll > 0 then
        -- Drawer.writeCentered(scroll.."/"..max, 65, height - 5, 5, 3, nil, nil, colors.blue)
        Button.addButton("v", function ()
            scroll = scroll - 1
            if scroll < 0 then
                scroll = 0
            end
        end, 65, height - 2, 5, 3, colors.blue, colors.white)
    end

    -- local i = 1
    -- for id, message in pairs(_messages) do
    --     print(#_messages, #_messages - height)
    --     if i > #_messages - height then
    --         monitor.setCursorPos(21, i - (#_messages - height))
    --         monitor.write(message.content) 
    --     end
    --     i = i + 1
    -- end
end

function _draw()
    monitor.clear()
    if auth_state == AUTH_STATE.NOT_AUTHENTICATED then
        monitor.setTextScale(3)
        local width, height = monitor.getSize()
        Drawer.writeCentered("Not authenticated", 1, 1, width, height)
    elseif auth_state == AUTH_STATE.AUTHENTICATING then
        monitor.setTextScale(3)
        local width, height = monitor.getSize()
        Drawer.writeCentered(dottedString("Authenticating"), 1, 1, width, height)
    elseif auth_state == AUTH_STATE.AUTHENTICATED then
        if not guilds then
            monitor.setTextScale(3)
            local width, height = monitor.getSize()    
            Drawer.writeCentered(dottedString("Loading"), 1, 1, width, height)
        else
            Button.clear()
            
            showGuilds(guilds)
            if selected_guild then
                if not channels then
                    monitor.setTextScale(1)
                    local width, height = monitor.getSize()
                    Drawer.writeCentered(dottedString("Loading channels"), 21, 1, 42, height)
                else
                    -- for id, channel in pairs(channels) do
                    --     print(id, channel)
                    -- end
                    showChannels(channels)
                    if selected_channel then
                        if messages ~= nil then
                            showMessages(messages)
                        else
                            monitor.setTextScale(1)
                            local width, height = monitor.getSize()
                            Drawer.writeCentered(dottedString("Loading messages"), 21, 1, 42, height)
                        end
                    else
                        monitor.setTextScale(1)
                        local width, height = monitor.getSize()
                        Drawer.writeCentered("Select a channel", 21, 1, 42, height)
                    end
                    if selected_channel and bots ~= nil then
                        showBots(bots)
                    end
                end
            end
            Button.draw()
        end
    end
end

function draw()
    while true do
        os.sleep(0.1)
        _draw()
    end
end

function main()
    while true do
        os.sleep(0.1)
        if auth_state == AUTH_STATE.NOT_AUTHENTICATED then
            auth_state = AUTH_STATE.AUTHENTICATING
            local saved_token = getSavedToken()
            if not saved_token then
                ws.send('{"type": "START_AUTH"}')
            else
                token = saved_token
                auth_state = AUTH_STATE.AUTHENTICATED
            end
        elseif auth_state == AUTH_STATE.AUTHENTICATED then
            if not guilds then
                if not token then
                    error("Token not found")
                end
                if #fetch_queue == 0 then
                    getGuilds()
                end
                -- print("token: "..token)
                -- print("Getting guilds...")
                -- print("Got guilds")
                -- print(guilds)
                -- for id, guild in pairs(channels) do
                --     print(channels.name)
                -- end
            end
            -- ws.send('{"type": "GET_MESSAGES"}')
            -- onMessage()
        end
    end
end

function sendMessage(_content)
    if not selected_channel or not selected_bot then return end

    local res = http.post("http://localhost:4000/message/send",
        textutils.serialiseJSON({
            token=token,
            channelId=selected_channel.id,
            content=_content,
            botName=selected_bot
        }),
        {["Content-Type"]="application/json"}
    ).readAll()
end

function editMessage(_content)
    if not being_edited or not selected_channel then return end

    local res = http.post("http://localhost:4000/message/edit",
        textutils.serialiseJSON({
            token=token,
            channelId=selected_channel.id,
            messageId=being_edited,
            content=_content,
            botName=editing_bot
        }),
        {["Content-Type"]="application/json"}
    ).readAll()
end

function chatHandler()
    while true do
        local event, username, message, uuid, isHidden = os.pullEvent("chat")
        if being_edited then
            editMessage(message)
            being_edited = nil
            editing_bot = nil
        else
            sendMessage(message)
        end
    end
end

function fetch(act)
    print("ADDING TO QUEUE")
    fetch_queue[#fetch_queue+1] = act
end

function fetcher()
    while true do
        os.sleep(0.1)
        if #fetch_queue > 0 then
            local act = table.remove(fetch_queue, 1)
            print("RUNNING FETCH")
            act()
        end
    end
end

parallel.waitForAny(main, onMessage, draw, tickDots, Button._handler, chatHandler, fetcher)

ws.close()