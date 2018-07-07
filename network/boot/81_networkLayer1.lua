local event = require "event"
local computer = require "computer"
local network = require "network"


----------------------- new

local interfaces

interfaces["sourceUUID"].type = "Ethenet"
interfaces["sourceUUID"].name = "eth0"
interfaces["sourceUUID"].driver = nil -- drivers[file]


local arpTable

-- Directly accessible. Send Frame via "sourceUUID" to "destinationUUID"
arpTable["destinationUUID"].mode = "direct"
arpTable["destinationUUID"].interface = "sourceUUID"
arpTable["destinationUUID"].lastSeen = 224898312839
arpTable["destinationUUID"].pathCost = 10

-- Accessible via gateway. Send Frame via "sourceUUID" to "gatewayUUID" as routed Frame with destination "destinationUUID2"
arpTable["destinationUUID2"].mode = "bridged"
arpTable["destinationUUID2"].interface = "sourceUUID"
arpTable["destinationUUID2"].via = "gatewayUUID"
arpTable["destinationUUID2"].lastSeen = 31118312839
arpTable["destinationUUID2"].pathCost = 429

-- On new data for "destinationUUIDx" check:
--  first: if old is too old, remove
--  if newer then old and path cheaper, exchange else keep.
--  if older then new one, keep.

-----------------------

-- Method for sending data over the node
local _rawSend

local getInterfaceInfo

local startNetwork

local dataHandler --Layer 2 data handler

local accessibleHosts
local nodes

------------------------
--Layer 1

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
        drivers[file] = {driver = loadfile("/lib/network/"..file)()}
        
        local eventHandler = {} -- Event Handers for the drivers to enable uplayer communication
        eventHandler.debug = print  -- DEBUG ENABLED
        --eventHandler.debug = function()end
        
               
        -- For driver to register a new host. DEPRECATED
        -- destinationUUID: the interfaceUUID that published its presence via STP
        -- mode: "bridged" or "direct"
        -- interfaceUUID is the receiver's interfaceUUID
        -- gatewayUUID is the sender's interfaceUUID, so where to send to to reach
        function eventHandler.nodeDiscovery(destinationUUID, mode, interfaceUUID, gatewayUUID, lastSeen, pathCost)

            -- check if we know interface[interfaceUUID]
            
            if mode == "direct" then
                print("New Arp Update for destinationNode "..destinationUUID.." on IF:"..interfaceUUID..". Cost: "..pathCost)
            else
                print("New Arp Update for destinationNode "..destinationUUID.." on IF:"..interfaceUUID.." via "..gatewayUUID..". Cost: "..pathCost)
            end
            
            -- get old arpTable[destinationUUID] if it existed

        end
        
        -- For the driver to register a new interface upon detection        
        function eventHandler.interfaceUp(name, sourceUUID, type)
            print("New interface: ", name, sourceUUID, type)            
            interfaces[sourceUUID].type = type
            interfaces[sourceUUID].name = name
            interfaces[sourceUUID].driver = drivers[file]            
        end
        
        -- For the driver to unregister a previously registered interface
        function eventHandler.interfaceDown(sourceUUID)
            -- TODO cleanup
        end
        
        -- For the driver to register received data on a node
        function eventHandler.recvData(data, node, origin)
            print("DEBUG: Received data on "..node.." from "..origin)
            -- dataHandler(data, node, origin)
        end
        
        -- For the driver to register a listener
        function eventHandler.setListener(evt, listener)
            return event.listen(evt, function(...)
                local args = {...}
                local res = {pcall(function()listener(table.unpack(args))end)}
                if not res[1] then
                    print("ERROR IN NET EVENTHANDLER["..file.."]:",res[2])
                end
                return table.unpack(res,2)
            end)
        end
        
        -- Start the driver and store the driver's event handler
        drivers[file].handle = drivers[file].driver.start(eventHandler)
    end
    
    -- Send data raw
    _rawSend = function(addr, node, data)
        print("TrySend:",node,addr,":",data)
        if accessibleHosts[addr] then
            accessibleHosts[addr].driver.driver.send(accessibleHosts[addr].driver.handle, node, addr, data)
        end
    end
    
    getInterfaceInfo = function(interfaceUUID)
        if interfaces[interfaceUUID] then        
            return interfaces[interfaceUUID].driver.info(interface)
        end
    end
    
    print("Layer 1 Networking stack initiated.")
    -- startNetwork()    
    computer.pushSignal("network_ready") -- maybe L1_ready
end

------------------------

-- On initialization start the networkLayer1Stack
event.listen("init", networkLayer1Stack)
