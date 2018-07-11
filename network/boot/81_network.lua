local event = require("event")
local computer = require("computer")
local network = require("network")
local logger = require("logging").getLogger("network")

----------------------- new

local interfaces = {}

--[[interfaces["sourceUUID"] = {}
interfaces["sourceUUID"].type = "Ethenet"
interfaces["sourceUUID"].name = "eth0"
interfaces["sourceUUID"].driver = nil -- drivers[file]
interfaces["sourceUUID"].handler = this drivers handler
]]

local topologyTable = {}
local topologyTableUpdated = false

-- Directly accessible. Send Frame via "sourceUUID" to "destinationUUID"
--[[topologyTable["destinationUUID"] = {
    mode = "direct",
    via = "sourceUUID",
    lastSeen = os.time(),
    pathCost = 10,
    gateway = ""
}

-- Accessible via gateway. Send Frame via "sourceUUID" to "gatewayUUID" as routed Frame with destination "destinationUUID2"
topologyTable["destinationUUID2"] = {
    mode = "bridged",
    via = "sourceUUID",
    gateway = "gatewayUUID",
    lastSeen = os.time(),
    pathCost = 429
}
]]


-- On new data for "destinationUUIDx" check:
--  first: if old is too old, remove
--  if newer then old and path cheaper, exchange else keep.
--  if older then new one, keep.


-----------------------

-- Method for sending data over the node

local getInterfaceInfo

local startNetwork

------------------------
local function getTopologyTable()
    return topologyTable
end

local function getInterfaces()
    return interfaces
end

------------------------
-- Layer 1

local initiated = false

local function networkDriver()
    if initiated then
        logger.log("Layer 1 Stack already initiated.")
        return
    end
    initiated = true

    local computer = require "computer"
    local filesystem = require "filesystem"

    --DRIVER INIT
    logger.log("Loading drivers...")

    -- Contains the library collection of the available drivers by name. drivers.[name]...
    local drivers = {}

    for file in filesystem.list("/lib/network") do

        logger.log("Loading driver:" .. file)
        drivers[file] = { driver = loadfile("/lib/network/" .. file)() }

        local eventHandler = {} -- Event Handers for the drivers to enable uplayer communication
        -- eventHandler.debug = logger.log -- DEBUG ENABLED
        eventHandler.debug = function()end

        --[[
            For the driver to register a new interface upon detection

            name:string - the name of the interface, like eth0
            sourceUUID:string - the uuid of the component, representing the interfaceUUID in the network.
            type:string - the type of connection this interface represents, like Ethernet, Tunnel
          ]]
        function eventHandler.interfaceUp(name, sourceUUID, type)
            logger.log("New interface: " .. name .. ", " .. sourceUUID .. ", " .. type)
            interfaces[sourceUUID] = {
                type = type,
                name = name,
                driver = drivers[file],
                handler = eventHandler
            }

            -- Add self reference to topology. this essentially is a loopback interface
            topologyTable[sourceUUID] = {
                mode = "direct",
                via = sourceUUID,
                gateway = "",
                lastSeen = os.time(), -- TODO needs to always be valid
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

            data:string - the data that was sent to this interface.
            interfaceUUID:string - the uuid of the receiving interface.
            sourceUUID:string - the original senter interfaceUUID that sent the data.
          ]]
        function eventHandler.recvData(data, interfaceUUID, sourceUUID)
            -- logger.log("DEBUG: Received data on " .. interfaceUUID .. " from " .. sourceUUID)
            computer.pushSignal("network_frame", sourceUUID, interfaceUUID, data)
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
            Returns the topology information of a known destinationUUID. This will also return NIL in case the destination
            is not known.
         ]]
        function eventHandler.getTopologyInformation(destinationUUID)
            return topologyTable[destinationUUID]
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
                    local oldPathCost = topologyTable[destinationUUID].pathCost

                    -- Old path is more expensive, so update with new path
                    if destinationUUID == senderInterfaceUUID then
                        topologyTable[destinationUUID] = {
                            mode = "direct",
                            via = receiverInterfaceUUID,
                            gateway = "",
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

                    logger.log("Updating new STTI: " .. destinationUUID .. ", " .. pathCost + distance .. ", " .. viaUUID .. "->" .. gatewayUUID .. ", " .. type .. ". Old path was" .. oldPathCost)

                    topologyTableUpdated = true
                end
            else
                -- Add the destination to the table
                if destinationUUID == senderInterfaceUUID then
                    topologyTable[destinationUUID] = {
                        mode = "direct",
                        via = receiverInterfaceUUID,
                        gateway = "",
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

                logger.log("Adding new STTI: " .. destinationUUID .. ", " .. pathCost + distance .. ", " .. viaUUID .. "->" .. gatewayUUID .. ", " .. type)

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
                    logger.log("ERROR IN NET EVENTHANDLER[" .. file .. "]:" .. res[2])
                end
                return table.unpack(res, 2)
            end)
        end

        -- Start the driver and store the driver's event handler
        drivers[file].handle = drivers[file].driver.start(eventHandler)
    end

    -- Send
    local sendFrame = function(destinationUUID, data)
        if not topologyTable[destinationUUID] then
            error("Destination unknown. Unable to send there.")
        else
            local sendingInterfaceUUID = topologyTable[destinationUUID].via
            interfaces[sendingInterfaceUUID].driver.driver.send(interfaces[sendingInterfaceUUID].handler, sendingInterfaceUUID, destinationUUID, data)
        end
    end

    getInterfaceInfo = function(interfaceUUID)
        if interfaces[interfaceUUID] then
            return interfaces[interfaceUUID].driver.info(interfaceUUID)
        end
    end


    -- Topology updating timertick
    event.timer(10, function()
        -- Update loopback interfaces' last seen time
        for interfaceUUID in pairs(interfaces) do
            topologyTable[interfaceUUID] = {
                mode = "direct",
                via = interfaceUUID,
                gateway = "",
                lastSeen = os.time(),
                pathCost = 0
            }
        end

        -- Clear out all outdated topology information
        for destinationUUID in pairs(topologyTable) do
            if (os.time() - topologyTable[destinationUUID].lastSeen) > 16 * 600 then
                logger.log("Discarding outdated topology entry for " .. destinationUUID)
                topologyTable[destinationUUID] = nil
                topologyTableUpdated = true
            end
        end

        if topologyTableUpdated then
            logger.log("Sending STTI because topology changed.")
            topologyTableUpdated = false

            for interfaceUUID in pairs(interfaces) do
                -- logger.log("Sending STTI update on " .. interfaceUUID)
                interfaces[interfaceUUID].driver.driver.sendSTTI(interfaceUUID, topologyTable)
            end
        end
    end, math.huge)

    -- Register L1 driver callbacks
    network.core.setCallback("getTopologyTable", getTopologyTable)
    network.core.setCallback("getInterfaces", getInterfaces)
    network.core.setCallback("sendFrame", sendFrame)

    logger.log("Layer 1 Networking stack initiated.")
    -- startNetwork()
    computer.pushSignal("network_ready") -- maybe L1_ready
end


------------------------

-- On initialization start the network
event.listen("init", networkDriver)
