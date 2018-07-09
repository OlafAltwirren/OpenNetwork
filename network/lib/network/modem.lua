--[[

 Communication on port 2992!

 Message types
 J/broadcast -> Join message of an interface to the topology {sourceUUID}
 T/unicast -> Publish of new STP topology table infos STTI. {sourceInterfaceUUID, distance, destinationUUID, pathCost, gatewayUUID, viaUUID, type}
 L/broadcast -> Leave message of an interface from the topology {sourceInterfaceUUID}
 P/unicast -> Passthrough message of a Frame to be passed on {sourceInterfaceUUID, senderInterfaceUUID, destinationUUID, ttl, data}
 D/unicast -> Direct Data for this interface. {sourceInterfaceUUID, destinationInterfaceUUID, data}

 ]]--

local component = require "component"
local event = require "event"

local vLanId = 2992
local ttlMax = 16

local driver = {}
local interfaces = {}

-- Structure
interfaces["interfaceUUID"] = {
    name = "ethX",
    pktIn = 0,
    pktOut = 0,
    bytesIn = 0,
    bytesOut = 0
}

local eventHnd



------------------------------- Internal functions -----------------------------


--[[
    TODO
 ]]
local function sendDirect(handle, interfaceUUID, destinationUUID, data)
    if interfaces[interfaceUUID] then
        if interfaceUUID == destinationUUID then
            -- Update statistics
            interfaces[interfaceUUID].pktOut = interfaces[interfaceUUID].pktOut + 1
            interfaces[interfaceUUID].bytesOut = interfaces[interfaceUUID].bytesOut + data:len()
            interfaces[interfaceUUID].pktIn = interfaces[interfaceUUID].pktIn + 1
            interfaces[interfaceUUID].bytesIn = interfaces[interfaceUUID].bytesIn + data:len()
            -- Route data back to self
            handle.recvData(data, interfaceUUID, destinationUUID)
        else
            -- Update statistics
            interfaces[interfaceUUID].pktOut = interfaces[interfaceUUID].pktOut + 1
            interfaces[interfaceUUID].bytesOut = interfaces[interfaceUUID].bytesOut + 1 + data:len()
            -- Send data to destination via source
            component.invoke(interfaceUUID, "send", destinationUUID, vLanId, "D"..data)
        end
    end
end

--[[
    TODO
 ]]
local function sendPassThrough(handle, interfaceUUID, destinationUUID, data)
    if interfaces[interfaceUUID] then
        if interfaceUUID == destinationUUID then
            -- TODO ERROR may not happen
            handle.debug("ERROR. Trying to pass through from same interface to gateway. May be an invalid topology table")
        else
            -- Update statistics
            interfaces[interfaceUUID].pktOut = interfaces[interfaceUUID].pktOut + 1
            interfaces[interfaceUUID].bytesOut = interfaces[interfaceUUID].bytesOut + 1 + data:len()
            -- Send data to destination via source
            component.invoke(interfaceUUID, "send", destinationUUID, vLanId, "P"..data)
        end
    end
end

local toByte = string.char

local function sizeToString(size)
    return toByte((size)%256) .. toByte(math.floor(size/256)%256) .. toByte(math.floor(size/65536)%256)
end

local function readSizeStr(str, pos)
    local len = str:sub(pos,pos):byte()
    return str:sub(pos+1, pos+len), len+1
end

--[[
    TODO
 ]]
local function decodeSTTI(data)
    --[pathCost-byte][destinationUUID.len-byte][destinationUUID][viaUUID.len-byte][viaUUID][gatewayUUID.len-byte][gatewayUUID][type.len-byte]{type]
    local pathCost = data:byte(2)
    local destinationUUID, destinationUUIDlen = readSizeStr(data, 3)
    local viaUUID, viaUUIDlen = readSizeStr(data, 3+destinationUUIDlen)
    local gatewayUUID, gatewayUUIDlen = readSizeStr(data, 3+destinationUUIDlen+viaUUIDlen)
    local type, typeLen = readSizeStr(data, 3+destinationUUIDlen+viaUUIDlen+gatewayUUIDlen)

    return destinationUUID, pathCost, viaUUID, gatewayUUID, type
end

--[[
    TODO
 ]]
local function encodeSTTI(destinationUUID, pathCost, viaUUID, gatewayUUID, type)
    --[pathCost-byte][destinationUUID.len-byte][destinationUUID][viaUUID.len-byte][viaUUID][gatewayUUID.len-byte][gatewayUUID][type.len-byte]{type]
    local composedData = toByte(pathCost)..toByte(destinationUUID:len())..destinationUUID..toByte(viaUUID:len())..viaUUID..toByte(gatewayUUID:len())..gatewayUUID..toByte(type:len())..type

    return composedData
end

--[[
    TODO
 ]]
local function decodePassThroughFrame(data)
    --[ttl-byte][originalSourceUUID.len-byte][originalSourceUUID][destinationUUID.len-byte][destinationUUID]passThroughData

    local ttl = data:byte(2)
    local originalSourceUUID, originalSourceUUIDlen = readSizeStr(data, 3)
    local destinationUUID, destinationUUIDlen = readSizeStr(data, 3+originalSourceUUIDlen)
    local passThroughData = data:sub(3+originalSourceUUIDlen+destinationUUIDlen)

    return originalSourceUUID, destinationUUID, ttl, passThroughData
end

--[[
    TODO
 ]]
local function encodePassThroughFrame(originalSourceUUID, destinationUUID, ttl, passThroughData)
    --[ttl-byte][originalSourceUUID.len-byte][originalSourceUUID][destinationUUID.len-byte][destinationUUID]passThroughData

    local composedData = toByte(ttl)..toByte(originalSourceUUID:len())..originalSourceUUID..toByte(destinationUUID:len())..destinationUUID..passThroughData

    return composedData
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
    layer1eventHandler.setListener("modem_message", driver.handleModelMessage)
    
    -- enumerate all interfaces for this driver and register them to L1
    local ifNumber = 0
    for modemUUID in component.list("modem", true) do
        layer1eventHandler.interfaceUp("eth"..tostring(ifNumber), modemUUID, "Ethernet")
        
        -- Setup internal table
        interfaces[modemUUID] = {            
            name = "eth"..tostring(ifNumber),
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

    -- TODO register for component add and remove

    return {}
end

--[[
    Handling all incoming modem_message events and decide that to do with them.
 ]]
function driver.handleModelMessage(_, interfaceUUID, sourceUUID, port, distance, data)
    -- Not a known interface this message is from. Ignore it.
    if not interfaces[interfaceUUID] then
        return
    end
    -- Not the correct vLanId. Ignore it.
    if port ~= vLanId then
        return
    end

    eventHnd.debug("Incoming Frame on "..interfaceUUID.." from "..sourceUUID..", distance "..distance)

    interfaces[interfaceUUID].pktIn = interfaces[interfaceUUID].pktIn + 1
    interfaces[interfaceUUID].bytesIn = interfaces[interfaceUUID].bytesIn + data:len()

    if data:sub(1,1) == "J" then
        -- Handle J/broadcast -> Join message of an interface to the topology {sourceUUID}
        eventHnd.debug("Join Message Received from "..sourceUUID..", distance "..distance)

        local pathCost
        if (distance > 0) then
            -- wireless message
            pathCost = 10 + distance
        else
            -- wired message
            pathCost = 5
        end
        -- Add new joined interface to own topology
        eventHnd.updateTopology(interfaceUUID, sourceUUID, pathCost, sourceUUID, 0, "", interfaceUUID, "direct")
    elseif data:sub(1,1) == "T" then
        -- Handle T/unicast -> Publish of new STP topology table infos STTI. {sourceInterfaceUUID, distance, destinationUUID, pathCost, gatewayUUID, viaUUID, type}
        eventHnd.debug("STTI Message Received from "..sourceUUID..", distance "..distance)

        local sttiDestinationUUID, sttiPathCost, sttiViaUUID, sttiGatewayUUID, sttiType = decodeSTTI(data)

        local pathCost
        if (distance > 0) then
            -- wireless message
            pathCost = 10 + distance
        else
            -- wired message
            pathCost = 5
        end

        eventHnd.updateTopology(interfaceUUID, sourceUUID, pathCost, sttiDestinationUUID, sttiPathCost, sttiGatewayUUID, sttiViaUUID, "bridged")

    elseif data:sub(1,1) == "L" then
        -- Handle L/broadcast -> Leave message of an interface from the topology {sourceInterfaceUUID}
        eventHnd.debug("Leave Message Received from "..sourceUUID)
        eventHnd.partFromTopology(interfaceUUID, sourceUUID)
    elseif data:sub(1,1) == "P" then
        -- Handle P/unicast -> Passthrough message of a Frame to be passed on {sourceInterfaceUUID, senderInterfaceUUID, destinationUUID, ttl, data}

        -- Decode passthrough frame
        local originalSourceUUID, destinationUUID, ttl, passThroughData = decodePassThroughFrame(data)

        -- in case we are the destination, give the data to the upper layer
        if interfaces[destinationUUID] then
            eventHnd.recvData(passThroughData, destinationUUID, originalSourceUUID)
        end

        -- in case the ttl has expored, drop that frame
        if ttl <= 0 then
            eventHnd.debug("Pass Through TTL frmo "..originalSourceUUID..", to "..destinationUUID.." has expired.")
            return
        end

        -- Get the topology information for the destination
        local topologyForDestination = eventHnd.getTopologyInformation(destinationUUID)
        if not topologyForDestination then
            -- Unknown destination, no knowledge where to send it to...
            eventHnd.debug("Destination "..destinationUUID.." not known to this node. TODO")
            return
        else
            if topologyForDestination.type == "direct" then
                -- we can directly send to the destination
                eventHnd.debug("Pass Through sent on directly to "..destinationUUID..", via "..topologyForDestination.via)
                sendDirect(eventHnd, topologyForDestination.via, destinationUUID, passThroughData)
            else
                -- we have to pass the frame content on
                eventHnd.debug("Pass Through sent on as pass-through to "..topologyForDestination.gateway..", via "..topologyForDestination.via)
                sendPassThrough(eventHnd, topologyForDestination.via, topologyForDestination.gateway, encodePassThroughFrame(originalSourceUUID, destinationUUID, ttl-1, passThroughData))
            end
        end
    elseif data:sub(1,1) == "D" then
        -- Handle D/unicast -> Direct Data for this interface. {sourceInterfaceUUID, destinationInterfaceUUID, data}
        eventHnd.recvData(data:sub(2), interfaceUUID, sourceUUID)
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
function driver.sendSTTI(interfaceUUID, destinationUUID, topologyInformation)

    -- encode STTI frame
    local data = encodeSTTI(destinationUUID, topologyInformation.pathCost, topologyInformation.via, topologyInformation.gateway, topologyInformation.mode)

    -- Update statistics
    interfaces[interfaceUUID].pktOut = interfaces[interfaceUUID].pktOut + 1
    interfaces[interfaceUUID].bytesOut = interfaces[interfaceUUID].bytesOut + 1 + data:len()
    -- Send data to destination via source
    component.invoke(interfaceUUID, "broadcast", vLanId, "T"..data)
end

--[[

    handle:interface - the driver to be used for callbakcs
 ]]
function driver.send(handle, interfaceUUID, destinationUUID, data)
    if interfaces[interfaceUUID] then
        if interfaceUUID == destinationUUID then
            -- Update statistics
            interfaces[interfaceUUID].pktOut = interfaces[interfaceUUID].pktOut + 1
            interfaces[interfaceUUID].bytesOut = interfaces[interfaceUUID].bytesOut + data:len()
            interfaces[interfaceUUID].pktIn = interfaces[interfaceUUID].pktIn + 1
            interfaces[interfaceUUID].bytesIn = interfaces[interfaceUUID].bytesIn + data:len()
            -- Route data back to self
            handle.recvData(data, interfaceUUID, destinationUUID)
        else
            -- Get the topology information for the destination
            local topologyForDestination = handle.getTopologyInformation(destinationUUID)

            if not topologyForDestination then
                -- Unknown destination, no knowledge where to send it to...
                handle.debug("Destination "..destinationUUID.." not known to this node. TODO")
                return
            else
                if topologyForDestination.type == "direct" then
                    -- we can directly send to the destination
                    handle.debug("Sending directly to "..destinationUUID..", via "..topologyForDestination.via)
                    sendDirect(handle, topologyForDestination.via, destinationUUID, data)
                else
                    -- we have to pass the frame content on
                    handle.debug("Sending pass-through to "..topologyForDestination.gateway..", via "..topologyForDestination.via)
                    sendPassThrough(handle, topologyForDestination.via, topologyForDestination.gateway, driver.encodePassThroughFrame(interfaceUUID, destinationUUID, ttlMax, data))
                end
            end
        end
    end
end

--[[
    TODO
 ]]
function driver.info(interface)
    if interfaces[interface] then
        return interfaces[interface].pktIn,interfaces[interface].pktOut,interfaces[interface].bytesIn,interfaces[interface].bytesOut
    end
    return 0,0,0,0
end

-----

return driver
