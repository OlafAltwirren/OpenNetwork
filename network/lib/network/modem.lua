--[[

Communication on port 2992!

Node protocol:
Hello/broadcast(sent by new host in node):  H (modem addersses are in event)
Hi/direct(sent by hosts to new host):       I (^)
Host quitting/broadcast                     Q (^)

STP update/broadcast                        S (^)

Data/direct                                 D[data] (origin from event)
Date/broadcast                              B[data] (origin from event)

]]

local component = require "component"
local event = require "event"

local driver = {}

local interfaces = {}

-- Structure
interfaces["interfaceUUID"].name = "ethX"
interfaces["interfaceUUID"].pktIn = 0
interfaces["interfaceUUID"].pktOut = 0
interfaces["interfaceUUID"].bytesIn = 0
interfaces["interfaceUUID"].bytesOut = 0

local eventHnd

function driver.start(eventHandler)
    eventHnd = eventHandler
    
    
    eventHandler.setListener("modem_message", function(_, interfaceUUID, sourceUUID, port, distance, data)
            --other kind of modem(possibly tunnel)
            if not interfaces[interfaceUUID] then
                return
            end 
            -- TODO check port
            
            eventHandler.debug("modemmsg["..interfaces[interfaceUUID].name.."]/"..sourceUUID..":"..data)
            
            interfaces[interfaceUUID].pktIn = interfaces[interfaceUUID].pktIn + 1
            interfaces[interfaceUUID].bytesIn = interfaces[interfaceUUID].bytesIn + data:len()
            
            if data:sub(1,1) == "H" then
                eventHandler.newHost(interfaceUUID, sourceUUID)
                component.invoke(interfaceUUID, "send", sourceUUID, 2992, "I")
                eventHandler.debug("REPL:",interfaceUUID,sourceUUID)
            elseif data:sub(1,1) == "I" then
                eventHandler.newHost(interfaceUUID, sourceUUID)
            elseif data:sub(1,1) == "Q" then
                eventHandler.delHost(interfaceUUID, sourceUUID)
            elseif data:sub(1,1) == "D" then
                eventHandler.recvData(data:sub(2), interfaceUUID, sourceUUID)
            elseif data:sub(1,1) == "B" then
                eventHandler.recvData(data:sub(2), interfaceUUID, sourceUUID)
            end
            
        end)
    
    -- enumerate all interfaces for this driver and register them to L1
    local ifNumber = 0
    for modemUUID in component.list("modem", true) do
        eventHandler.interfaceUp("eth"..tostring(ifNumber), modemUUID, "Ethernet")
        
        -- Setup internal table
        interfaces[modemUUID] = {            
            name = "eth"..tostring(ifNumber),
            pktIn = 0,
            pktOut = 1,
            bytesIn = 0,
            bytesOut = 1
        }
                
        component.invoke(int, "open", 1)
        
        -- Publish presence via STP Publish rather component.invoke(int, "broadcast", 1, "H")
        
        c = c + 1
    end
    return {}
end

function driver.send(handle, interfaceUUID, destinationUUID, data)
    if interfaces[interfaceUUID] then
        if interfaceUUID == destinationUUID then
            -- Update statistics
            interfaces[interfaceUUID].pktOut = interfaces[interfaceUUID].pktOut + 1
            interfaces[interfaceUUID].bytesOut = interfaces[interfaceUUID].bytesOut + data:len()
            interfaces[interfaceUUID].pktIn = interfaces[interfaceUUID].pktIn + 1
            interfaces[interfaceUUID].bytesIn = interfaces[interfaceUUID].bytesIn + data:len()
            -- Route data back to self
            eventHnd.recvData(data, interfaceUUID, destinationUUID)        
        else
            -- Update statistics
            interfaces[interface].pktOut = interfaces[interface].pktOut + 1
            interfaces[interface].bytesOut = interfaces[interface].bytesOut + 1 + data:len()
            -- Send data to destination via source
            component.invoke(sourceUUID, "send", destinationUUID, 2992, "D"..data)
        end
    end
end

function driver.info(interface)
    if interfaces[interface] then
        return interfaces[interface].pktIn,interfaces[interface].pktOut,interfaces[interface].bytesIn,interfaces[interface].bytesOut
    end
    return 0,0,0,0
end

return driver
