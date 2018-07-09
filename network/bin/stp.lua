--
-- Created by IntelliJ IDEA.
-- User: FinFarenath
-- Date: 08.07.2018
-- Time: 12:27
-- To change this template use File | Settings | File Templates.
--

local libLayer1network = require("libLayer1network")

local function fillText(text, n)
    for k = 1, n - #text do
        text = text .. " "
    end
    return text
end

local maxlen = {8, 5}

local viaTable = {}

-- Create inverse reference table
for destinationUUID, topologyEntry in pairs(libLayer1network.stp.getTopologyTable()) do
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
    print("  "..via..":")
    for struct in pairs(structList) do
        print("    "..struct.destination.."  "..struct.mode.."  "..fillText(struct.path, 4).." "..fillText(struct.gateway, 12).." "..struct.age)
    end
end
