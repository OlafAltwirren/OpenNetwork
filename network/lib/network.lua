local computer = require("computer")
local event = require("event")
local logging = require("logging")

-- keep all links to the dirver for the networkLayer1.lua
local driver = {}

-- public functions
local network = {}
local internal = {}

------------
-- Core communication
network.core = {}

function network.core.setCallback(name, fn)
    driver[name] = fn
end

function network.core.lockCore()
    network.core = nil
end

------------


------------
-- STP - Spanning Tree Protocol

network.stp = {}
internal.stp = {}


function network.stp.getTopologyTable()
    if not driver.getTopologyTable then
        print("Layer1 Network demon not loaded.")
        return {}
    else
        return driver.getTopologyTable()
    end
end

function network.stp.getInterfaces()
    if not driver.getTopologyTable then
        print("Layer1 Network demon not loaded.")
        return {}
    else
        return driver.getInterfaces()
    end
end

------------

-- (I) ICMP - Internet Control and Management Protocol

network.icmp = {}
internal.icmp = {
    logger = logging.getLogger("icmp")
}

local pingid = 0

--[[
    Send a layer 1 STP based ping frame.
 ]]
function network.icmp.ping(sourceUUID, destinationUUID, payload)
    pingid = pingid + 1
    driver.sendFrame(sourceUUID, destinationUUID, nil, "IP" .. computer.address() .. ":" .. tostring(pingid) .. ":" .. payload)
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
            internal.icmp.logger.debug("ICMP Echo reply from " .. sourceUUID .. ", id " .. id)
            computer.pushSignal("stp_ping_reply", sourceUUID, interfaceUUID, tonumber(id), payload)
        else
            internal.icmp.logger.debug("ICMP Echo request from " .. sourceUUID .. " to " .. interfaceUUID .. ", id " .. id)
            driver.sendFrame(nil, sourceUUID, nil, data)
        end
    end
end


------------

-- (N) INP - Internet Naming Protocol

--[[
    Definitions:
        Host -> the name of the host. This name can be bound to one interfaceUUIDs on this computer.
        Network -> the network name this host is part of. There may be multple networks hosts are part of. Network names start with "."
        Domain -> Combination of a Host and Network name. Uniquely identifying this host in this network.

    Query for name:
        Ask all known interfaceUUIDs via unicast for the name resolution.
    Answer to a name query:
        Send the own registered names back.

 ]]

network.inp = {}
internal.inp = {
    maxNameAge = 3600, -- amount of seconds to keep a name in the cache until it is deemed outdated
    maxNameQueryWait = 30, -- amount of seconds to wait for a name query reply
    logger = logging.getLogger("inp"),
    nameTable = {}, -- mapping from "host.network" -> interfaceUUID
    interfaceTable = {}, -- mapping from interfaceUUID.["host.network"] -> existing
    nameCache = {} -- mapping from domainName --> { interface, lastSeen }
}

--[[
    TODO
 ]]
function network.inp.bindDomainName(domainName, interfaceUUID)
    if not internal.inp.nameTable[domainName] then
        internal.inp.nameTable[domainName] = {}
    end
    internal.inp.nameTable[domainName] = interfaceUUID
    if not internal.inp.interfaceTable[interfaceUUID] then
        internal.inp.interfaceTable[interfaceUUID] = {}
    end
    internal.inp.interfaceTable[interfaceUUID][domainName] = {}
    -- Add to local cache
    network.inp.updateNameCache(domainName, interfaceUUID, true)
end

--[[
    TODO
 ]]
function network.inp.removeInterface(interfaceUUID)
    -- unbind all domains previously bound to this interface
    for domainName in pairs(internal.inp.interfaceTable[interfaceUUID]) do
        internal.inp.logger.debug("Removing domain " .. domainName .. " from interface " .. interfaceUUID)
        internal.inp.nameTable[domainName] = nil
        -- Also clear cache
        internal.inp.nameCache[domainName] = nil
    end
    internal.inp.interfaceTable[interfaceUUID] = nil
end

--[[
    TODO
 ]]
function network.inp.updateNameCache(domainName, interfaceUUID, authorative)
    internal.inp.nameCache[domainName] = {
        interface = interfaceUUID,
        lastSeen = os.time(),
        authorative = authorative
    }
end

--[[
    TODO
 ]]
function network.inp.getMaxCacheAge()
    return internal.inp.maxNameAge
end

--[[
    TODO
 ]]
function network.inp.getNameCache()
    return internal.inp.nameCache
end

--[[
    TODO
    returns the found interfaceUUID or NIL in case none was found.
 ]]
function network.inp.getInterfaceForDomainName(domainName)
    if internal.inp.nameCache[domainName] then
        if os.time() - internal.inp.nameCache[domainName].lastSeen < internal.inp.maxNameAge or internal.inp.nameCache[domainName].authorative then
            -- return cached name
            return internal.inp.nameCache[domainName].interface
        end
    end
    -- try to resolve name
    for destinationUUID, topologyEntry in pairs(network.stp.getTopologyTable()) do
        if topologyEntry.via ~= destinationUUID then -- don't send to self
            internal.inp.logger.debug("INP Query for Name " .. domainName .. " to " .. destinationUUID)
            driver.sendFrame(nil, destinationUUID, nil, "NQ" .. domainName)
        end
    end
    -- wait 10 seconds for a reply
    local eventName, foundDomainName, foundInterfaceUUID = event.pull(10, "inp_name_found")
    if eventName == "inp_name_found" and foundDomainName == domainName then
        return foundInterfaceUUID
    else
        return nil
    end
end

--[[
    TODO
 ]]
function internal.inp.handle(sourceUUID, interfaceUUID, data)
    if data:sub(2, 2) == "Q" then -- Query for name
        local domainName = data:sub(3)
        -- TODO currencly no wildcards. Only exact match.
        if internal.inp.nameTable[domainName] then
            internal.icmp.logger.debug("INP Respond with name-found for " .. domainName .. " as " .. internal.inp.nameTable[domainName] .. " to " .. sourceUUID)
            driver.sendFrame(nil, sourceUUID, nil, "NR" .. domainName .. ":" .. internal.inp.nameTable[domainName])
        end
    elseif data:sub(2, 2) == "R" then -- Response to name query
        local matcher = data:sub(3):gmatch("[^:]+")
        local domainName = matcher()
        local foundInterfaceUUID = matcher()
        network.inp.updateNameCache(domainName, foundInterfaceUUID, false)
        internal.icmp.logger.debug("INP received name-found for " .. domainName .. " as " .. foundInterfaceUUID)
        computer.pushSignal("inp_name_found", domainName, foundInterfaceUUID)
    end
end

------------

-- (U) UDP - User Datagram Protocol

--[[
    Definitions:

 ]]

network.udp = {}
internal.udp = {
    logger = logging.getLogger("udp"),
    ports = {}
}

--[[
    TODO
 ]]
function internal.udp.checkPortRange(port)
    if port < 0 or port > 65535 then internal.udp.logger.error("Incorrect Portnumber. Need to be in range 0..65535") end
end

--[[
    TODO
 ]]
function network.udp.listen(port)
    internal.udp.checkPortRange(port)
    internal.udp.ports[port] = true
end

--[[
    TODO
 ]]
function network.udp.close(port)
    internal.udp.checkPortRange(port)
    internal.udp.ports[port] = nil
end

--[[
    TODO
 ]]
function network.udp.send(destinationUUID, port, data)
    internal.udp.checkPortRange(port)
    -- Send from suitable source with default TTL
    driver.sendFrame(nil, destinationUUID, nil, "U" .. string.char(math.floor(port / 256)) .. string.char(port % 256) .. data)
end

--[[
    TODO
 ]]
function internal.udp.handle(sourceUUID, interfaceUUID, data)
    local port = data:byte(2) * 256 + data:byte(3)
    if internal.udp.ports[port] then
        -- internal.udp.ports[port].callback(sourceUUID, port, data:sub(4))
        internal.udp.logger.debug("Incoming datagram from " .. sourceUUID .. " to " .. interfaceUUID .. " on port " .. port)
        computer.pushSignal("datagram", sourceUUID, port, data:sub(4))
    end
end

------------
-- Data processing

event.listen("network_frame", function(_, sourceUUID, interfaceUUID, data)
    internal.icmp.logger.debug("Got network_frame from " .. sourceUUID .. ". Protocol " .. data:sub(1, 1))
    if data:sub(1, 1) == "I" then
        internal.icmp.handle(sourceUUID, interfaceUUID, data)
    elseif data:sub(1, 1) == "N" then
        internal.inp.handle(sourceUUID, interfaceUUID, data)
    elseif data:sub(1, 1) == "U" then
        internal.udp.handle(sourceUUID, interfaceUUID, data)
    end
end)

------------

return network
