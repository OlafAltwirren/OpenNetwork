local event = require("event")
local computer = require("computer")
local network = require("network")
local logger = require("logging").getLogger("network")
local logging = require("logging")

----------------------- new

local maxTtl = 16
local sttiDiscardAge = 5 * 60 * 20 -- minutes x seconds x ticks
local sttiUpdateIntervall = 60 -- seconds between checking and sending topology updates

local interfaces = {}
--[[
    interfaces["sourceUUID"] = {
        type = "Ethenet",
        name = "eth0",
        driver = drivers[file],
        handler = the eventHandler of the networkDriver used by the componentDriver
]]

local topologyTable = {}
--[[
    topologyTable["destinationUUID2"] = {  destinationUUID:string - final destination of the interfaceUUID
        mode = "bridged", - "bridged","direct","loop" - "bridged", when this interfaceis not directly reachable by this interface. "direct" when the destinationUUID is directly reachable via this interfaceUUID
        via = "sourceUUID", - via:string - the interfaceUUID through which the fame shall be sent to reach  the destinationUUID. This interface needs to be local to this node.
        gateway = "gatewayUUID", gateway:string - the interfaceUUID to which the frame shall be sent to reach its final destination.
        lastSeen = os.time(),
        pathCost = 429
 ]]

local topologyTableUpdated = false


-----------------------

local getInterfaceInfo

local startNetwork

--[[
    Returns the structure of this node's topology table.
 ]]
local function getTopologyTable()
    return topologyTable
end

--[[
    Returns this node's list of known interfaces.
 ]]
local function getInterfaces()
    return interfaces
end

------------------------
-- Layer 1

local initialized = false

local function initLayer1Driver()
    if initialized then
        logger.info("Layer 1 stack already initiated.")
        return
    end
    initialized = true

    local computer = require("computer")
    local filesystem = require("filesystem")

    --[[
           This will select the appropriate driver for sending a frame via the given sourceUUID to the destinationUUID.

           sourceUUID:string       - the interfaceUUID to send from. In case this is NIL, the interface is automatically selected.
           destinationUUID:string  - the interfaceUUID of the destination to send the data to.
           ttl:int                 - may be NIL for default or a given TTL to be used for sending
           data:string             - the arbitrary data to send.
        ]]
    local sendFrame = function(originalSourceUUID, finalDestinationUUID, ttl, data)
        if not ttl then
            ttl = maxTtl
        end
        if not topologyTable[finalDestinationUUID] then
            logger.error("Destination unknown. Unable to send there.")
        else
            -- set correct sneder
            local sendingInterfaceUUID
            if originalSourceUUID then
                if interfaces[originalSourceUUID] then
                    sendingInterfaceUUID = originalSourceUUID
                else
                    -- sending as pass-through
                    sendingInterfaceUUID = topologyTable[finalDestinationUUID].via
                end
            else
                -- no sourceUUID given, try to select the appropriate one
                sendingInterfaceUUID = topologyTable[finalDestinationUUID].via
                originalSourceUUID = sendingInterfaceUUID
            end

            logger.debug("Sending Frame from " .. originalSourceUUID .. " to " .. finalDestinationUUID .. "; protocol " .. data:sub(1, 1))

            interfaces[sendingInterfaceUUID].driver.driver.sendFrameViaDriver(interfaces[sendingInterfaceUUID].handler, -- handler for callbacks / this one
                sendingInterfaceUUID, -- interface where to send from ::gatewayUUID
                topologyTable[finalDestinationUUID].gateway, -- final destinationUUID, the driver decided wether this is direct or needs to be routed
                originalSourceUUID,
                finalDestinationUUID,
                data,
                ttl)
        end
    end


    -- Layer 0 driver init
    logger.info("Loading drivers...")

    -- Contains the library collection of the available drivers by name. drivers.[name]...
    local drivers = {}

    for file in filesystem.list("/lib/network") do

        logger.info("Loading driver:" .. file)
        drivers[file] = { driver = loadfile("/lib/network/" .. file)() }

        local eventHandler = {} -- Event Handers for the drivers to enable communication to layer 1

        eventHandler.logger = logging.getLogger(file)

        --[[
            For the driver to register a new interface upon detection

            name:string - the name of the interface, like eth0
            sourceUUID:string - the uuid of the component, representing the interfaceUUID in the network.
            type:string - the type of connection this interface represents, like Ethernet, Tunnel
          ]]
        function eventHandler.interfaceUp(name, sourceUUID, type)
            logger.info("New interface: " .. name .. ", " .. sourceUUID .. ", " .. type)
            interfaces[sourceUUID] = {
                type = type,
                name = name,
                driver = drivers[file],
                handler = eventHandler
            }

            -- Add self reference to topology. this essentially is a loopback interface
            topologyTable[sourceUUID] = {
                mode = "loop",
                via = sourceUUID,
                gateway = "",
                lastSeen = os.time(),
                pathCost = 0
            }
        end

        --[[
            For the driver to unregister a previously registered interface

            TODO
          ]]
        function eventHandler.interfaceDown(sourceUUID)
            -- TODO cleanup
        end

        --[[
            For the driver to register received data on a node. This is to be passed on to higher network layers.

            sourceUUID:string - the original senter interfaceUUID that sent the data.
            destinationUUID:string - the destinationUUID of the data.
            ttl:int - the time to live of this data
            data:string - the data that was received
          ]]
        function eventHandler.onReceiveFrame(sourceUUID, destinationUUID, ttl, data)
            -- check wether this data is for us
            if interfaces[destinationUUID] then
                -- this data is for us
                logger.debug("Received frame from "..sourceUUID.." to "..destinationUUID)
                computer.pushSignal("network_frame", sourceUUID, destinationUUID, data)
            else
                -- this data is to be send on
                if not ttl then
                    ttl = maxTtl
                end
                logger.debug("Passing on frame from "..sourceUUID.." to "..destinationUUID..", "..tostring(ttl))
                sendFrame(sourceUUID, destinationUUID, ttl-1, data)
            end
        end

        --[[
            Remove an interface from the topology and update it accordingly.

            receiverInterfaceUUID:string - the interfaceUUID of the interface receiving the message.
            partingInterfaceUUID:string - the interfaceUUID of the interface parting from the network.
         ]]
        function eventHandler.partFromTopology(receiverInterfaceUUID, partingInterfaceUUID)

            -- TODO
            -- Remove destination as partingInterfaceUUID from topology
            -- Announce new topology
        end

        --[[
            Update of the topology from the network.

            interfaceUUID, sourceUUID
            I,S,15:S,0,S,d -> S,15,I,d  -- loopback on other node, same as sending STTI
            I,S,15:A,0,A,d -> A,15,I->S,b  -- loopback on other node, another as sending STTI
            I,S,15:C,14,S,d -> C,15+14,I->S,b -- directly reachable interface from sender of STTI
            I,S,15:D,7,S->X,b -> D,15+7,I->S,b -- bridged reachable interface from STTI sender's interface on
            I,S,15:E,11,A->Y,b -> D,15+11,I->S,b -- bridged reachable interface from other then STTI sender's interface

            I,S,N:D,P,X->Y,T -> D,N+P,I->S,b

            receiverInterfaceUUID:string - the interfaceUUID of the interface receiving this STTI.
            senderInterfaceUUID:string - the interfaceUUID of the interface that sent the STTI.
            distance:int - the path cost of the STTI frame received.
            destinationUUID:string - the final destinationUUID for the STP table
            pathCost:int - the pathCost for the path to the destiationUUID from the sourceInterfaceUUID's point of view
            gatewayUUID:string - NIL in case type=="direct", otherwise the destinationUUID to pass the frame on for reaching the destinationUUID
            viaUUID:string - the interface to be used to send to destinationUUID. Eigther to sent ot the gateway to reach it or directly
            type:string - may be "direct" or "passthrough"
            lastSeen:int - os.time() of last seen
            forcePublish:boolean - forces publishing of updates
         ]]
        function eventHandler.updateTopology(receiverInterfaceUUID, senderInterfaceUUID, distance, destinationUUID, pathCost, gatewayUUID, viaUUID, type, lastSeen, forcePublish)
            -- Heed forcePublish flag
            if forcePublish then
                topologyTableUpdated = true
            end

            -- get existing entry from topology
            if topologyTable[destinationUUID] then
                if topologyTable[destinationUUID].pathCost > pathCost + distance then
                    -- Old path is more expensive, so update with new path
                    local oldPathCost = topologyTable[destinationUUID].pathCost

                    if destinationUUID == senderInterfaceUUID then
                        topologyTable[destinationUUID] = {
                            mode = "direct",
                            via = receiverInterfaceUUID,
                            gateway = destinationUUID,
                            lastSeen = lastSeen,
                            pathCost = pathCost + distance,
                        }
                    else
                        topologyTable[destinationUUID] = {
                            mode = "bridged",
                            via = receiverInterfaceUUID,
                            gateway = senderInterfaceUUID,
                            lastSeen = lastSeen,
                            pathCost = pathCost + distance,
                        }
                    end

                    logger.debug("Updating new STTI: " .. destinationUUID .. ", " .. pathCost + distance .. ", " .. viaUUID .. "->" .. gatewayUUID .. ", " .. type .. ". Old path was" .. oldPathCost)

                    topologyTableUpdated = true
                end
            else
                -- Add the destination to the table
                if destinationUUID == senderInterfaceUUID then
                    topologyTable[destinationUUID] = {
                        mode = "direct",
                        via = receiverInterfaceUUID,
                        gateway = destinationUUID,
                        lastSeen = lastSeen,
                        pathCost = pathCost + distance,
                    }
                else
                    topologyTable[destinationUUID] = {
                        mode = "bridged",
                        via = receiverInterfaceUUID,
                        gateway = senderInterfaceUUID,
                        lastSeen = lastSeen,
                        pathCost = pathCost + distance,
                    }
                end

                logger.debug("Adding new STTI: " .. destinationUUID .. ", " .. pathCost + distance .. ", " .. viaUUID .. "->" .. gatewayUUID .. ", " .. type)

                topologyTableUpdated = true
            end
        end

        --[[
            For the driver to register a listener Callback listener registration.

            evt:?
            listener:?
            TODO
          ]]
        function eventHandler.setListener(evt, listener)
            return event.listen(evt, function(...)
                local args = { ... }
                local res = { pcall(function() listener(table.unpack(args)) end) }
                if not res[1] then
                    logger.error("ERROR IN NET EVENTHANDLER[" .. file .. "]:" .. res[2])
                end
                return table.unpack(res, 2)
            end)
        end

        -- Start the driver and store the driver's event handler
        drivers[file].handle = drivers[file].driver.start(eventHandler)
    end

    --[[
        Return the interface statistics and information based on the interdaces UUID.
     ]]
    getInterfaceInfo = function(interfaceUUID)
        if interfaces[interfaceUUID] then
            return interfaces[interfaceUUID].driver.info(interfaceUUID)
        end
    end

    -- Topology updating timertick
    event.timer(sttiUpdateIntervall, function()
        -- Update loopback interfaces' last seen time
        for interfaceUUID in pairs(interfaces) do
            topologyTable[interfaceUUID] = {
                mode = "loop",
                via = interfaceUUID,
                gateway = interfaceUUID,
                lastSeen = os.time(),
                pathCost = 0
            }
        end

        -- Clear out all outdated topology information
        for destinationUUID in pairs(topologyTable) do
            if (os.time() - topologyTable[destinationUUID].lastSeen) > sttiDiscardAge then
                logger.debug("Discarding outdated topology entry for " .. destinationUUID)
                topologyTable[destinationUUID] = nil
                topologyTableUpdated = true
            end
        end

        if topologyTableUpdated then
            logger.debug("Sending STTI because topology changed.")
            topologyTableUpdated = false

            for interfaceUUID in pairs(interfaces) do
                logger.trace("Sending STTI update on " .. interfaceUUID)
                interfaces[interfaceUUID].driver.driver.sendSTTI(interfaceUUID, topologyTable)
            end
        end
    end, math.huge)

    -- Register L1 driver callbacks
    network.core.setCallback("getTopologyTable", getTopologyTable)
    network.core.setCallback("getInterfaces", getInterfaces)
    network.core.setCallback("sendFrame", sendFrame)

    logger.info("Layer 1 Networking stack initiated.")
    -- startNetwork()
    computer.pushSignal("network_ready")
end

------------------------

-- On initialization start the network
event.listen("init", initLayer1Driver)
