local network = require("network")
local fileconfig = require("fileconfig")
local event = require("event")
local computer = require("computer")
local logger = require("logging").getLogger("hostname")

local defaultHostnameConfig = {}

event.listen("network_ready", function()
    pcall(function()
        -- create default config
        for interfaceUUID, interfaceStruct in pairs(network.stp.getInterfaces()) do
            defaultHostnameConfig[interfaceUUID] = {}
            table.insert(defaultHostnameConfig[interfaceUUID], interfaceStruct.name .. "-" .. computer.address())
        end

        -- load config
        logger.log("Loading INP configuration...")
        local hostnameConfig = fileconfig.loadConfig("inp.json", defaultHostnameConfig)

        -- process config

        for interfaceUUID in pairs(hostnameConfig) do
            logger.log("Binding hostnames for interface "..interfaceUUID)
            for domainName in pairs(hostnameConfig[interfaceUUID]) do
                logger.log("Binding "..domainName.." to interface "..interfaceUUID) -- TOOD use eth0 or such instead of UUID
                network.inp.bindDomainName(domainName, interfaceUUID)
            end
        end

    end)
end)
