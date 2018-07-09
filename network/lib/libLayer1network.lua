local computer = require("computer")
local event = require("event")
local logging = require("logging")

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
internal.icmp = {
    logger = logging.getLogger("icmp")
}

local pingid = 0

--[[
    Send a layer 1 STP based ping frame.
 ]]
function libLayer1network.icmp.ping(destinationUUID, payload)
    pingid = pingid + 1
    driver.sendFrame(destinationUUID, "IP" .. computer.address() .. ":" .. tostring(pingid) .. ":" .. payload)
    return pingid
end

--[[
    Handle ICMP protocol specific data
 ]]
function internal.icmp.handle(sourceUUID, interfaceUUID, data)
    if data:sub(2, 2) == "P" then
        local matcher = data:sub(3):gmatch("[^:]+")
        local compid = matcher()
        local id = tonumber(matcher())
        local payload = matcher()
        if compid == computer.address() then
            internal.icmp.logger.log("ICMP Echo reply from "..sourceUUID..", id "..id)
            computer.pushSignal("stp_ping_reply", sourceUUID, interfaceUUID, tonumber(id), payload)
        else
            internal.icmp.logger.log("ICMP Echo request from "..sourceUUID..", id "..id)
            driver.sendFrame(sourceUUID, data)
        end
    end
end

------------
-- Data processing

event.listen("network_frame", function(_, sourceUUID, interfaceUUID, data)
    internal.icmp.logger.log("Got network_frame from "..sourceUUID..". Protocol "..data:sub(1, 1))
    if data:sub(1, 1) == "I" then
        internal.icmp.handle(sourceUUID, interfaceUUID, data)
        --elseif data:sub(1,1) == "T" then internal.tcp.handle(origin, data)
        -- elseif data:sub(1,1) == "D" then internal.udp.handle(origin, data)
    end
end)

------------

return libLayer1network