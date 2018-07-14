--[[

 Communication on port 2992!

 Message types
 J/broadcast -> Join message of an interface to the topology {sourceUUID}
 B/broadcast -> Beacon message, telling the others this interface is still there. {sourceUUID}
 T/unicast -> Publish of new STP topology table infos STTI. {sourceInterfaceUUID, distance, destinationUUID, pathCost, gatewayUUID, viaUUID, type}
 L/broadcast -> Leave message of an interface from the topology {sourceInterfaceUUID}
 P/unicast -> Passthrough message of a Frame to be passed on {sourceInterfaceUUID, senderInterfaceUUID, destinationUUID, ttl, data}
 D/unicast -> Direct Data for this interface. {sourceInterfaceUUID, destinationInterfaceUUID, data}

 ]] --

local component = require "component"
local event = require "event"

local vLanId = 2992

local driver = {}
local interfaces = {}

-- Structure
--[[interfaces["interfaceUUID"] = {
    name = "ethX",
    pktIn = 0,
    pktOut = 0,
    bytesIn = 0,
    bytesOut = 0
}
]]
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
    local composedData = toByte(math.floor(pathCost + 0.5)) .. toByte(destinationUUID:len()) .. destinationUUID .. toByte(viaUUID:len()) .. viaUUID .. toByte(gatewayUUID:len()) .. gatewayUUID .. toByte(type:len()) .. type .. toByte(lastSeenStr:len()) .. lastSeenStr

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
local function encodePassThroughFrame(originalSourceUUID, destinationUUID, ttl, passThroughData)
    --[ttl-byte][originalSourceUUID.len-byte][originalSourceUUID][destinationUUID.len-byte][destinationUUID]passThroughData

    local composedData = toByte(ttl) .. toByte(originalSourceUUID:len()) .. originalSourceUUID .. toByte(destinationUUID:len()) .. destinationUUID .. passThroughData

    return composedData
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
    for modemUUID in component.list("modem", true) do
        layer1eventHandler.interfaceUp("eth" .. tostring(ifNumber), modemUUID, "Ethernet")

        -- Setup internal table
        interfaces[modemUUID] = {
            name = "eth" .. tostring(ifNumber),
            pktIn = 0,
            pktOut = 1,
            bytesIn = 0,
            bytesOut = 1
        }

        -- Open interface on the vLanId port number for communication
        component.invoke(modemUUID, "open", vLanId)

        -- Publish presence via STP Join
        component.invoke(modemUUID, "broadcast", vLanId, "J")
        ifNumber = ifNumber + 1
    end

    -- Refresh own interfaces periodically
    event.timer(60, function()
        for interfaceUUID in pairs(interfaces) do
            eventHnd.debug("Broadcasting beacon for " .. interfaceUUID)
            component.invoke(interfaceUUID, "broadcast", vLanId, "B")
        end
    end, math.huge)

    -- TODO register for component add and remove

    return {}
end

--[[
    Handling all incoming modem_message events and decide that to do with them.
 ]]
function driver.handleModemMessage(_, interfaceUUID, sourceUUID, port, distance, data)
    -- Not a known interface this message is from. Ignore it.
    if not interfaces[interfaceUUID] then
        return
    end
    -- Not the correct vLanId. Ignore it.
    if port ~= vLanId then
        return
    end

    -- eventHnd.debug("Incoming Frame on " .. interfaceUUID .. " from " .. sourceUUID .. ", distance " .. distance)

    updatePacketStats(interfaceUUID, 1, data:len(), 0, 0)

    if data:sub(1, 1) == "J" then
        -- Handle J/broadcast -> Join message of an interface to the topology {sourceUUID}
        eventHnd.debug("Join Message Received from " .. sourceUUID .. ", distance " .. distance)

        local pathCost
        if (distance > 0) then
            -- wireless message
            pathCost = 10 + math.floor(distance + 0.5)
        else
            -- wired message
            pathCost = 5
        end
        -- Add new joined interface to own topology
        eventHnd.updateTopology(interfaceUUID, -- where was it received
            sourceUUID, -- who send the frame
            pathCost, -- how expensice was sending this to here?
            sourceUUID, -- who sent it
            0, -- what is the destinations's path cost so far
            sourceUUID, -- what is the gatewayUUID to be used to read the destinationUUID, none in this case, as we can directly reach it.
            interfaceUUID, -- what is the interface to send via
            "direct", -- mode of sending data to this destination
            os.time(), -- last seen is now
            true) -- force an update, becasue a beacon refreshes the timestamp of this interface
    elseif data:sub(1, 1) == "B" then
        -- Handle B/broadcast -> Join message, telling the others this interface is still there. {sourceUUID}
        eventHnd.debug("Beacon Message Received from " .. sourceUUID .. ", distance " .. distance)

        local pathCost
        if (distance > 0) then
            -- wireless message
            pathCost = 10 + math.floor(distance + 0.5)
        else
            -- wired message
            pathCost = 5
        end
        -- Add new joined interface to own topology
        eventHnd.updateTopology(interfaceUUID, -- where was it received
            sourceUUID, -- who send the frame
            pathCost, -- how expensice was sending this to here?
            sourceUUID, -- who sent it
            0, -- what is the destinations's path cost so far
            sourceUUID, -- what is the gatewayUUID to be used to read the destinationUUID, none in this case, as we can directly reach it.
            interfaceUUID, -- what is the interface to send via
            "direct", -- mode of sending data to this destination
            os.time(), -- last seen is now
            false) -- force an update, becasue a beacon refreshes the timestamp of this interface
    elseif data:sub(1, 1) == "T" then
        -- Handle T/unicast -> Publish of new STP topology table infos STTI. {sourceInterfaceUUID, distance, destinationUUID, pathCost, gatewayUUID, viaUUID, type}
        eventHnd.debug("STTI Message Received from " .. sourceUUID .. ", distance " .. distance)

        local pathCost
        if (distance > 0) then
            -- wireless message
            pathCost = 10 + math.floor(distance + 0.5)
        else
            -- wired message
            pathCost = 5
        end

        local compountSTTI = data:sub(2)
        while compountSTTI:len() > 0 do
            local sttiDestinationUUID, sttiPathCost, sttiViaUUID, sttiGatewayUUID, sttiType, lastSeen, length = decodeSTTI(compountSTTI)
            -- eventHnd.debug("Decoded STTI for "..sttiDestinationUUID)
            compountSTTI = compountSTTI:sub(length)
            eventHnd.updateTopology(interfaceUUID, sourceUUID, pathCost, sttiDestinationUUID, sttiPathCost, sttiGatewayUUID, sttiViaUUID, sttiType, lastSeen, false)
        end

    elseif data:sub(1, 1) == "L" then
        -- Handle L/broadcast -> Leave message of an interface from the topology {sourceInterfaceUUID}
        eventHnd.debug("Leave Message Received from " .. sourceUUID)
        eventHnd.partFromTopology(interfaceUUID, sourceUUID)
    elseif data:sub(1, 1) == "P" then
        -- Handle P/unicast -> Passthrough message of a Frame to be passed on {sourceInterfaceUUID, senderInterfaceUUID, destinationUUID, ttl, data}
        eventHnd.debug("Received pass-through on " .. interfaceUUID .. " from " .. sourceUUID)

        -- Decode passthrough frame
        local originalSourceUUID, destinationUUID, ttl, passThroughData = decodePassThroughFrame(data)

        -- in case the ttl has expored, drop that frame
        if ttl <= 0 then
            eventHnd.debug("Pass Through TTL frmo " .. originalSourceUUID .. ", to " .. destinationUUID .. " has expired.")
            return
        end

        eventHnd.onReceiveFrame(originalSourceUUID, destinationUUID, ttl, passThroughData)

    elseif data:sub(1, 1) == "D" then
        -- Handle D/unicast -> Direct Data for this interface. {sourceInterfaceUUID, destinationInterfaceUUID, data}
        eventHnd.debug("Received data on " .. interfaceUUID .. " from " .. sourceUUID)

        eventHnd.onReceiveFrame(sourceUUID, interfaceUUID, nil, data:sub(2))
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
    component.invoke(interfaceUUID, "broadcast", vLanId, "T" .. data)
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
                handle.debug("Sending data via loopback on " .. interfaceUUID)
                handle.onReceiveFrame(sourceUUID, destinationUUID, ttl, data)
            else
                -- Update statistics
                updatePacketStats(interfaceUUID, 0, 0, 1, data:len())
                -- Send data to destination via source
                handle.debug("Sending D data via " .. interfaceUUID .. " to " .. destinationUUID)
                component.invoke(interfaceUUID, "send", destinationUUID, vLanId, "D" .. data)
            end
        else
            -- we want to send via pass-through
            local passThroughData = encodePassThroughFrame(sourceUUID, destinationUUID, ttl, data)
            -- Update statistics
            updatePacketStats(interfaceUUID, 0, 0, 1, passThroughData:len())
            -- Send data to destination via source
            handle.debug("Sending P data via " .. interfaceUUID .. " to " .. gatewayUUID..". PT from "..sourceUUID..", to "..destinationUUID)
            component.invoke(interfaceUUID, "send", gatewayUUID, vLanId, "P" .. passThroughData)
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
