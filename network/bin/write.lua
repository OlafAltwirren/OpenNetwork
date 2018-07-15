local network = require("network")
local event = require("event")
local term = require("term")
local shell = require("shell")

local args, options = shell.parse(...)

if #args < 2 or options.h or options.help then
    print("Usage: write [hostname] [port]")
    print("  -v   --verbose             Output more details")
    return
end

local function verbose(...)
    if options.v or options.verbose then
        print(...)
    end
end

local port = tonumber(args[2])
local hostname = args[1]
local remoteUUID = network.inp.getInterfaceForDomainName(hostname)

if not remoteUUID  then
    error("Unknown Hostname.")
end

if port < 0 then error("Unspecified port")end
if not listen and not hostname then error("Unspecified hostname")end


local function handleUdp()
    while true do
        local e = {event.pull() }
        -- "datagram", sourceUUID, port, data
        if e[1] then
            if e[1] == "datagram" then
                if e[2] == remoteUUID and e[3] == port then
                    term.write(e[4])
                end
            elseif e[1] == "key_up" then
                network.udp.send(remoteUUID, port, string.char(e[3]))
                term.write(string.char(e[3]))
            end
        end
    end
end

local state, reason = pcall(function()
    remoteUUID = network.udp.listen(port)
    handleUdp()
end)

if not state then
    verbose("Stopped by: " .. tostring(reason))
end

network.udp.close(port)

