local network = require("network")
local event = require("event")
local computer = require("computer")
local shell = require("shell")

local args, options = shell.parse(...)

local function fillText(text, n)
    for k = 1, n - #text do
        text = text .. " "
    end
    return text
end

local function round(n, r) return math.floor(n * (10 ^ r)) / (10 ^ r) end

local function showHelp()
    print("Usage: dig: [domain][.network] [option]")
    print("  -l   --list                Lists this node's name cache")
    print("  -v   --verbose             Output more details")
    return
end

local function verbose(...)
    if options.v or options.verbose then
        print(...)
    end
end

if options.h or options.help then
    showHelp()
end

local state, reason = pcall(function()
    if options.l or options.list then
        print(" Cache content of this node:")
        for domainName, cacheStruct in pairs(network.inp.getNameCache()) do
            local authorativeFlag = " "
            local timeOut = os.time() - cacheStruct.lastSeen
            local timeOutString
            if cacheStruct.authorative then
                authorativeFlag = "*"
                timeOutString = ""
            else
                if timeOut > network.inp.getMaxCacheAge() then
                    timeOutString = "outdated"
                else
                    timeOutString = tostring(timeOut)
                end
            end
            print(" " .. authorativeFlag .. " " .. fillText(domainName, 20) .. "   " .. cacheStruct.interface .. "  " .. fillText(, 5))
        end
        print(" -- *=authorative")
    else
        if #args < 1 then
            showHelp()
        end
        print("DIG for " .. args[1])
        local interfaceUUID = network.inp.getInterfaceForDomainName(args[1])
        if interfaceUUID then
            print(" Found " .. args[1] .. " -> " .. interfaceUUID)
        else
            print(" Unknown host " .. args[1])
        end
    end
end)

if not state then
    verbose("Stopped by: " .. tostring(reason))
end

