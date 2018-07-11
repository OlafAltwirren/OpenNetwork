local network = require("network")
local event = require("event")
local computer = require("computer")
local shell = require("shell")

local args, options = shell.parse(...)

if #args < 1 or options.h or options.help then
    print("Usage: dig: [domain][.network]")
    print("  -v   --verbose             Output more details")
    return
end

local function round(n, r) return math.floor(n * (10 ^ r)) / (10 ^ r) end

local function verbose(...)
    if options.v or options.verbose then
        print(...)
    end
end

print("DIG for " .. args[1])

local state, reason = pcall(function()
    local interfaceUUID = network.inp.getInterfaceForDomainName(args[1])
    if interfaceUUID then
        print(" Found "..args[1].." -> "..interfaceUUID)
    else
        print(" Unknown host "..args[1])
    end
end)

if not state then
    verbose("Stopped by: " .. tostring(reason))
end

