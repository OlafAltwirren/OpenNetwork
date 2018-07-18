--[[

 No ports for tunnels

 Message types
 J/unicast -> Join message of an interface to the topology {sourceUUID}
 B/unicast -> Beacon message, telling the others this interface is still there. {sourceUUID}
 T/unicast -> Publish of new STP topology table infos STTI. {sourceInterfaceUUID, distance, destinationUUID, pathCost, gatewayUUID, viaUUID, type}
 L/unicast -> Leave message of an interface from the topology {sourceInterfaceUUID}
 P/unicast -> Passthrough message of a Frame to be passed on {sourceInterfaceUUID, senderInterfaceUUID, destinationUUID, ttl, data}
 D/unicast -> Direct Data for this interface. {sourceInterfaceUUID, destinationInterfaceUUID, data}

 ]] --

local component = require "component"
local event = require "event"

local beaconIntervall = 60

-- This layer 0 driver's functions
local driver = {}
local interfaces = {}
--[[
    interfaces["interfaceUUID"] = {
        name = "ethX",
        pktIn = 0,
        pktOut = 0,
        bytesIn = 0,
        bytesOut = 0
    }
]]

-- This tunnel interfaces partner interfaceUUID
local tunnelPartnerUUID = ""

-- Reference to the Layer 1 eventHandler for callbacks
local eventHnd

------------------------------- Internal functions -----------------------------

local toByte = string.char

local function sizeToString(size)
    return toByte((size) % 256) .. toByte(math.floor(size / 256) % 256) .. toByte(math.floor(size / 65536) % 256)
end

local function readSizeStr(str, pos)
    local len = str:sub(pos, pos):byte()
    return str:sub(pos + 1, pos + len), len + 1
end

--[[
    TODO
 ]]
local function decodeSTTI(data)
    --[pathCost-byte][destinationUUID.len-byte][destinationUUID][viaUUID.len-byte][viaUUID][gatewayUUID.len-byte][gatewayUUID][type.len-byte]{type]
    local pathCost = data:byte(1)
    local destinationUUID, destinationUUIDlen = readSizeStr(data, 2)
    local viaUUID, viaUUIDlen = readSizeStr(data, 2 + destinationUUIDlen)
    local gatewayUUID, gatewayUUIDlen = readSizeStr(data, 2 + destinationUUIDlen + viaUUIDlen)
    local type, typeLen = readSizeStr(data, 2 + destinationUUIDlen + viaUUIDlen + gatewayUUIDlen)
    local lastSeenStr, lastSeenStrLen = readSizeStr(data, 2 + destinationUUIDlen + viaUUIDlen + gatewayUUIDlen + typeLen)
    local lastSeen = tonumber(lastSeenStr)

    return destinationUUID, pathCost, viaUUID, gatewayUUID, type, lastSeen, 2 + destinationUUIDlen + viaUUIDlen + gatewayUUIDlen + typeLen + lastSeenStrLen
end

--[[
    TODO
 ]]
local function encodeSTTI(destinationUUID, pathCost, viaUUID, gatewayUUID, type, lastSeen)
    --[pathCost-byte][destinationUUID.len-byte][destinationUUID][viaUUID.len-byte][viaUUID][gatewayUUID.len-byte][gatewayUUID][type.len-byte]{type][lastSeen.len-byte][lastSeen]
    local lastSeenStr = tostring(lastSeen)
    local composedData = toByte(pathCost) .. toByte(destinationUUID:len()) .. destinationUUID .. toByte(viaUUID:len()) .. viaUUID .. toByte(gatewayUUID:len()) .. gatewayUUID .. toByte(type:len()) .. type ..toByte(lastSeenStr:len()) .. lastSeenStr

    return composedData
end

--[[
    TODO
 ]]
local function encodePassThroughFrame(originalSourceUUID, destinationUUID, ttl, passThroughData)
    --[ttl-byte][originalSourceUUID.len-byte][originalSourceUUID][destinationUUID.len-byte][destinationUUID]passThroughData

    local composedData = toByte(ttl) .. toByte(originalSourceUUID:len()) .. originalSourceUUID .. toByte(destinationUUID:len()) .. destinationUUID .. passThroughData

    return composedData
end


--[[
    TODO
 ]]
local function decodePassThroughFrame(data)
    --[ttl-byte][originalSourceUUID.len-byte][originalSourceUUID][destinationUUID.len-byte][destinationUUID]passThroughData

    local ttl = data:byte(2)
    local originalSourceUUID, originalSourceUUIDlen = readSizeStr(data, 3)
    local destinationUUID, destinationUUIDlen = readSizeStr(data, 3 + originalSourceUUIDlen)
    local passThroughData = data:sub(3 + originalSourceUUIDlen + destinationUUIDlen)

    return originalSourceUUID, destinationUUID, ttl, passThroughData
end

--[[
    TODO
 ]]
local function updatePacketStats(interfaceUUID, pktIn, bytesIn, pktOut, bytesOut)
    interfaces[interfaceUUID].pktOut = interfaces[interfaceUUID].pktOut + pktOut
    interfaces[interfaceUUID].bytesOut = interfaces[interfaceUUID].bytesOut + bytesOut
    interfaces[interfaceUUID].pktIn = interfaces[interfaceUUID].pktIn + pktIn
    interfaces[interfaceUUID].bytesIn = interfaces[interfaceUUID].bytesIn + bytesIn
end

-------------------------------------- API Implementations for the driver ---------------------------------------------

--[[
    Start the driver. This shall register all known interfaces of this kind the driver manages, register its callback listeners
    and startup the communication on the network.

    layer1eventHandler:interface - the layer1 handle for callbacks
 ]]
function driver.start(layer1eventHandler)

    eventHnd = layer1eventHandler

    -- Register event handler for kind of modem_message
    layer1eventHandler.setListener("modem_message", driver.handleModemMessage)

    -- enumerate all interfaces for this driver and register them to L1
    local ifNumber = 0
    for modemUUID in component.list("tunnel", true) do
        layer1eventHandler.interfaceUp("tun" .. tostring(ifNumber), modemUUID, "Tunnel")

        -- Setup internal table
        interfaces[modemUUID] = {
            name = "tun" .. tostring(ifNumber),
            pktIn = 0,
            pktOut = 1,
            bytesIn = 0,
            bytesOut = 1
        }

        -- Publish presence via STP Join
        component.invoke(modemUUID, "send", "J")
        ifNumber = ifNumber + 1
    end

    -- Refresh own interfaces periodically
    event.timer(beaconIntervall, function()
        for interfaceUUID in pairs(interfaces) do
            eventHnd.logger.debug("Sending beacon for " .. interfaceUUID)
            component.invoke(interfaceUUID, "send", "B")
        end
    end, math.huge)

    -- TODO register for component add and remove

    return {}
end



--[[
    Handling all incoming modem_message events and decide that to do with them.
 ]]
function driver.handleModemMessage(_, interfaceUUID, partnerUUID, _, _, data)
    -- Not a known interface this message is from. Ignore it.
    if not interfaces[interfaceUUID] then
        eventHnd.logger.trace("Incoming frame on " .. interfaceUUID .. " from " .. partnerUUID .. " not for known interfaces.")
        return
    end

    eventHnd.logger.trace("Incoming Frame on " .. interfaceUUID .. " from " .. partnerUUID)
    updatePacketStats(interfaceUUID, 1, data:len(), 0, 0)

    if data:sub(1, 1) == "J" then
        -- Handle J/unicast -> Join message of an interface to the topology {sourceUUID}
        eventHnd.logger.debug("Join Message Received from partner " .. partnerUUID)

        -- Set partner of tunnel
        tunnelPartnerUUID = partnerUUID

        -- Add new joined interface to own topology
        eventHnd.updateTopology(interfaceUUID, partnerUUID, 0, partnerUUID, 0, partnerUUID, interfaceUUID, "direct", os.time(), true)
    elseif data:sub(1, 1) == "B" then
        -- Handle B/unicast-> Beacon message, telling the others this interface is still there. {sourceUUID}
        eventHnd.logger.debug("Beacon Message Received from " .. partnerUUID)

        -- Set partner of tunnel
        tunnelPartnerUUID = partnerUUID

        -- Add new joined interface to own topology
        eventHnd.updateTopology(interfaceUUID, partnerUUID, 0, partnerUUID, 0, partnerUUID, interfaceUUID, "direct", os.time(), false)
    elseif data:sub(1, 1) == "T" then
        -- Handle T/unicast -> Publish of new STP topology table infos STTI. {sourceInterfaceUUID, distance, destinationUUID, pathCost, gatewayUUID, viaUUID, type}
        eventHnd.logger.debug("STTI Message Received from " .. partnerUUID)

        local compountSTTI = data:sub(2)
        while compountSTTI:len() > 0 do
            local sttiDestinationUUID, sttiPathCost, sttiViaUUID, sttiGatewayUUID, sttiType, lastSeen, length = decodeSTTI(compountSTTI)
            -- eventHnd.debug("Decoded STTI for "..sttiDestinationUUID)
            compountSTTI = compountSTTI:sub(length)

            eventHnd.updateTopology(interfaceUUID, partnerUUID, 0, sttiDestinationUUID, sttiPathCost, sttiGatewayUUID, sttiViaUUID, sttiType, lastSeen, false)
        end
    elseif data:sub(1, 1) == "L" then
        -- Handle L/unicast -> Leave message of an interface from the topology {sourceInterfaceUUID}
        eventHnd.logger.debug("Leave Message Received from " .. partnerUUID)

        -- Remove partner of tunnel
        tunnelPartnerUUID = ""

        eventHnd.partFromTopology(interfaceUUID, partnerUUID)
    elseif data:sub(1, 1) == "P" then
        -- Handle P/unicast -> Passthrough message of a Frame to be passed on {sourceInterfaceUUID, senderInterfaceUUID, destinationUUID, ttl, data}
        eventHnd.logger.debug("Received pass-through on " .. interfaceUUID.. " from "..partnerUUID)

        -- Decode passthrough frame
        local originalSourceUUID, destinationUUID, ttl, passThroughData = decodePassThroughFrame(data)

        -- in case the ttl has expored, drop that frame
        if ttl <= 0 then
            eventHnd.logger.debug("Pass Through TTL from " .. originalSourceUUID .. ", to " .. destinationUUID .. " has expired.")
            return
        end

        eventHnd.onReceiveFrame(originalSourceUUID, destinationUUID, ttl, passThroughData)
    elseif data:sub(1, 1) == "D" then
        -- Handle D/unicast -> Direct Data for this interface. {sourceInterfaceUUID, destinationInterfaceUUID, data}
        eventHnd.logger.debug("Received data on " .. interfaceUUID.. " from "..partnerUUID)

        eventHnd.onReceiveFrame(partnerUUID, interfaceUUID, nil, data:sub(2))
    end
end

--[[
    Send STTI with the given topologyInformation to all neighbors

    interfaceUUID:string
    destinationUUID:string
    topologyInformation:struct
       mode:string
       via:string
       gateway:string
       lastSeen:int
       pathCost:int
 ]]
function driver.sendSTTI(interfaceUUID, topologyInformation)
    --Format [STTI][STTI]...
    local data = ""
    for destinationUUID in pairs(topologyInformation) do
        -- encode STTI frame
        data = data .. encodeSTTI(destinationUUID, topologyInformation[destinationUUID].pathCost, topologyInformation[destinationUUID].via, topologyInformation[destinationUUID].gateway, topologyInformation[destinationUUID].mode, topologyInformation[destinationUUID].lastSeen)
    end

    -- Update statistics
    interfaces[interfaceUUID].pktOut = interfaces[interfaceUUID].pktOut + 1
    interfaces[interfaceUUID].bytesOut = interfaces[interfaceUUID].bytesOut + 1 + data:len()
    -- Send data to destination via source
    component.invoke(interfaceUUID, "send", "T" .. data)
end

--[[

    handle:interface - the driver to be used for callbakcs
 ]]
function driver.sendFrameViaDriver(handle, interfaceUUID, gatewayUUID, sourceUUID, destinationUUID, data, ttl)
    if interfaces[interfaceUUID] then
        -- see wether we want to send direct
        if interfaceUUID == sourceUUID and gatewayUUID == destinationUUID then
            -- we want to send directly
            if sourceUUID == destinationUUID then
                -- Update statistics
                updatePacketStats(interfaceUUID, 1, data:len(), 1, data:len())
                -- Route data back to self
                handle.logger.debug("Sending data via loopback on " .. interfaceUUID)
                handle.onReceiveFrame(sourceUUID, destinationUUID, ttl, data)
            else
                -- Update statistics
                updatePacketStats(interfaceUUID, 0, 0, 1, data:len())
                -- Send data to destination via source
                handle.logger.debug("Sending D data via " .. interfaceUUID .. " to " .. destinationUUID)
                component.invoke(interfaceUUID, "send", "D" .. data)
            end
        else
            -- we want to send via pass-through
            local passThroughData = encodePassThroughFrame(sourceUUID, destinationUUID, ttl, data)
            -- Update statistics
            updatePacketStats(interfaceUUID, 0, 0, 1, passThroughData:len())
            -- Send data to destination via source
            handle.logger.debug("Sending P data via " .. interfaceUUID .. " to " .. gatewayUUID..". PT from "..sourceUUID..", to "..destinationUUID)
            component.invoke(interfaceUUID, "send", "P" .. passThroughData)
        end
    end
end

--[[
    TODO
 ]]
function driver.info(interface)
    if interfaces[interface] then
        return interfaces[interface].pktIn, interfaces[interface].pktOut, interfaces[interface].bytesIn, interfaces[interface].bytesOut
    end
    return 0, 0, 0, 0
end

-----

return driver
