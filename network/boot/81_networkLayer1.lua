local event = require "event"
local computer = require "computer"
local libLayer1network = require "libLayer1network"


----------------------- new

local interfaces = {}

interfaces["sourceUUID"] = {}
interfaces["sourceUUID"].type = "Ethenet"
interfaces["sourceUUID"].name = "eth0"
interfaces["sourceUUID"].driver = nil -- drivers[file]


local topologyTable = {}
local topologyTableUpdated = false

-- Directly accessible. Send Frame via "sourceUUID" to "destinationUUID"
topologyTable["destinationUUID"] = {}
topologyTable["destinationUUID"].mode = "direct"
topologyTable["destinationUUID"].via = "sourceUUID"
topologyTable["destinationUUID"].lastSeen = 224898312839
topologyTable["destinationUUID"].pathCost = 10

-- Accessible via gateway. Send Frame via "sourceUUID" to "gatewayUUID" as routed Frame with destination "destinationUUID2"
topologyTable["destinationUUID2"] = {}
topologyTable["destinationUUID2"].mode = "bridged"
topologyTable["destinationUUID2"].via = "sourceUUID"
topologyTable["destinationUUID2"].gateway = "gatewayUUID"
topologyTable["destinationUUID2"].lastSeen = 31118312839
topologyTable["destinationUUID2"].pathCost = 429

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

local function networkLayer1Stack()
    if initiated then
        return
    end
    initiated = true

    local computer = require "computer"
    local filesystem = require "filesystem"

    --DRIVER INIT
    print("Loading drivers...")

    -- Contains the library collection of the available drivers by name. drivers.[name]...
    local drivers = {}

    for file in filesystem.list("/lib/network") do

        print("Loading driver:", file)
        drivers[file] = { driver = loadfile("/lib/network/" .. file)() }

        local eventHandler = {} -- Event Handers for the drivers to enable uplayer communication
        eventHandler.debug = print -- DEBUG ENABLED
        --eventHandler.debug = function()end

        --[[
            For the driver to register a new interface upon detection

            name:string - the name of the interface, like eth0
            sourceUUID:string - the uuid of the component, representing the interfaceUUID in the network.
            type:string - the type of connection this interface represents, like Ethernet, Tunnel
          ]]
        function eventHandler.interfaceUp(name, sourceUUID, type)
            print("New interface: ", name, sourceUUID, type)
            interfaces[sourceUUID] = {
                type = type,
                name = name,
                driver = drivers[file]
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
            print("DEBUG: Received data on " .. interfaceUUID .. " from " .. sourceUUID)
            -- TODO
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

            receiverInterfaceUUID:string - the interfaceUUID of the interface receiving this STTI.
            senderInterfaceUUID:string - the interfaceUUID of the interface that sent the STTI.
            distance:int - the path cost of the STTI frame received.
            destinationUUID:string - the final destinationUUID for the STP table
            pathCost:int - the pathCost for the path to the destiationUUID from the sourceInterfaceUUID's point of view
            gatewayUUID:string - NIL in case type=="direct", otherwise the destinationUUID to pass the frame on for reaching the destinationUUID
            viaUUID:string - the interface to be used to send to destinationUUID. Eigther to sent ot the gateway to reach it or directly
            type:string - may be "direct" or "passthrough"
         ]]
        function eventHandler.updateTopology(receiverInterfaceUUID, senderInterfaceUUID, distance, destinationUUID, pathCost, gatewayUUID, viaUUID, type)
            -- get existing entry from topology
            if topologyTable[destinationUUID] then
                if topologyTable[destinationUUID].pathCost >= pathCost + distance then
                    local oldPathCost = topologyTable[destinationUUID].pathCost

                    -- Old path is more expensive, so update with new path
                    topologyTable[destinationUUID].mode = type
                    topologyTable[destinationUUID].via = receiverInterfaceUUID
                    topologyTable[destinationUUID].gateway = senderInterfaceUUID
                    topologyTable[destinationUUID].lastSeen = os.time
                    topologyTable[destinationUUID].pathCost = pathCost + distance

                    print("updating new STTI: " .. destinationUUID .. ", " .. pathCost .. ", " .. viaUUID .. "->" .. gatewayUUID .. ", " .. type .. ". Old path was" .. oldPathCost)

                    topologyTableUpdated = true
                end
            else
                -- Add the destination to the table
                topologyTable[destinationUUID] = {
                    mode = type,
                    via = receiverInterfaceUUID,
                    gateway = senderInterfaceUUID,
                    lastSeen = os.time,
                    pathCost = pathCost + distance
                }

                print("Adding new STTI: " .. destinationUUID .. ", " .. pathCost .. ", " .. viaUUID .. "->" .. gatewayUUID .. ", " .. type)

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
                    print("ERROR IN NET EVENTHANDLER[" .. file .. "]:", res[2])
                end
                return table.unpack(res, 2)
            end)
        end

        -- Start the driver and store the driver's event handler
        drivers[file].handle = drivers[file].driver.start(eventHandler)
    end

    -- Send data raw

    getInterfaceInfo = function(interfaceUUID)
        if interfaces[interfaceUUID] then
            return interfaces[interfaceUUID].driver.info(interfaceUUID)
        end
    end

    print("Layer 1 Networking stack initiated.")
    -- startNetwork()    
    computer.pushSignal("network_ready") -- maybe L1_ready

    -- TODO start timed publish of updated topology


    -- Register L1 driver callbacks
    libLayer1network.core.setCallback("getTopologyTable", getTopologyTable)
    libLayer1network.core.setCallback("getInterfaces", getInterfaces)
end

------------------------

-- On initialization start the networkLayer1Stack
event.listen("init", networkLayer1Stack)
