local computer = require("computer")

-- keep all links to the dirver for the networkLayer1.lua
local driver = {}

-- public functions
local libLayer1network = {}
local internal = {}

------------
-- Core communication
libLayer1network.core = {}

function libLayer1network.core.setCallback(name, fn)
    driver[name] = fn
end

function libLayer1network.core.lockCore()
    libLayer1network.core = nil
end

------------


------------
-- STP

libLayer1network.stp = {}
internal.stp = {}


function libLayer1network.stp.getTopologyTable()
    if not driver.getTopologyTable then
        print("Layer1 Network demon not loaded.")
        return {}
    else
        return driver.getTopologyTable()
    end
end

function libLayer1network.stp.getInterfaces()
    if not driver.getTopologyTable then
        print("Layer1 Network demon not loaded.")
        return {}
    else
        return driver.getInterfaces()
    end
end

------------

-- ICMP
libLayer1network.icmp = {}
internal.icmp = {}

local pingid = 0

function libLayer1network.icmp.ping(destinationUUID, payload)
    pingid = pingid + 1
    driver.sendFrame(destinationUUID, "I"..computer.address()..":"..tostring(pingid)..":"..payload)
    return pingid
end

function internal.icmp.handle(origin, data)
    if data:sub(2,2) == "P" then
        local matcher = data:sub(3):gmatch("[^:]+")
        local compid = matcher()
        local id = tonumber(matcher())
        local payload = matcher()
        if compid == computer.address() then
            computer.pushSignal("ping_reply", origin, tonumber(id), payload)
        else
            driver.send(origin, data)
        end
    end
end

------------

return libLayer1network