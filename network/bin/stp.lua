--
-- Created by IntelliJ IDEA.
-- User: FinFarenath
-- Date: 08.07.2018
-- Time: 12:27
-- To change this template use File | Settings | File Templates.
--

local network = require("network")

local function fillText(text, n)
    for k = 1, n - #text do
        text = text .. " "
    end
    return text
end

local maxlen = { 8, 5 }

local viaTable = {}

-- Create inverse reference table
for destinationUUID, topologyEntry in pairs(network.stp.getTopologyTable()) do
    if not viaTable[topologyEntry.via] then
        viaTable[topologyEntry.via] = {}
    end
    table.insert(viaTable[topologyEntry.via], {
        destination = destinationUUID,
        path = topologyEntry.pathCost,
        gateway = topologyEntry.gateway,
        mode = topologyEntry.mode,
        age = os.time() - topologyEntry.lastSeen
    })
end

print("Topology via STP")
print("")
for via, structList in pairs(viaTable) do
    print("  " .. via .. ":")
    for _, struct in pairs(structList) do
        if (struct.destination == via) and (struct.mode == "direct") and (struct.path == 0) then
            print("    " .. struct.destination .. "  " .. fillText("loopback",8) .. "                                            " .. tostring(struct.age))
        else
            print("    " .. struct.destination .. "  " .. fillText(struct.mode,8) .. "  " .. fillText(tostring(math.floor(struct.path+0.5)), 4) .. " " .. fillText(struct.gateway, 36) .. " " .. tostring(struct.age))
        end
    end
end
