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

for destinationUUID, topologyEntry in ipairs(libLayer1network.stp.getTopologyTable()) do
    print(destinationUUID..","..topologyEntry.pathCost..", "..topologyEntry.via.."->"..topologyEntry.gateway..", "..topologyEntry.mode.." @"..topologyEntry.lastSeen)

end

