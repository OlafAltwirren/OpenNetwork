local libLayer1network = require("libLayer1network")
local libconfig = require("libconfig")
local event = require("event")
local computer = require("computer")
local logger = require("logging").getLogger("hostname")

local defaultHostnameConfig = {}

event.listen("network_ready", function()
    pcall(function()
        -- create default config
        for interfaceUUID, interfaceStruct in pairs(libLayer1network.stp.getInterfaces()) do
            defaultHostnameConfig[interfaceUUID] = {}
            table.insert(defaultHostnameConfig[interfaceUUID], interfaceStruct.name .. "-" .. computer.address())
        end

        -- load config
        local hostnameConfig = libconfig.loadConfig("inp.cfg", defaultHostnameConfig)

        -- process config

        for interfaceUUID in pairs(hostnameConfig) do
            for domainName in pairs(hostnameConfig[interfaceUUID]) do
                logger.log("Binding "..domainName.." to interface "..interfaceUUID) -- TOOD use eth0 or such instead of UUID
                libLayer1network.inp.bindDomainName(domainName, interfaceUUID)
            end
        end

    end)
end)
