--[[
    Library fileconfig

    Loads configuration.
    If file doesn't exist, creates new one with given defaultCfg

    Example defaultCfg:

    Variables in configuration can be then read by they names:

    fileconfig = require("fileconfig")
    configuration = fileconfig.loadConfig("filename.json", {
        defaultElement = {
            name = "value"
        },
        defaultArray = { "1", "2", "3" }
    })

    print(configuration["defaultElement"].name)

    Results:
        string "value"

    Requires:
        - json > 0.1.1
        - OpenComputers > 1.7
        - OpenOS > 1.7

    Author:
        Olaf Altwirren ( olaf.altwirren@airflowrental.de )
 ]]

fileconfig = {
    _version = "0.1"
}

local filesystem = require("filesystem")
local json = require("json")

-------------------------------------- Internal Helpers and Functions ---------------------------------------------

--[[
    TODO
 ]]
local function readAll(file)
    local f = io.open(file, "rb")
    if f then
        local content = f:read("*all")
        f:close()
        return content
    else
        return nil
    end
end

-------------------------------------- API Functions and Methods ---------------------------------------------

--[[
    TODO
 ]]
function fileconfig.loadConfig(configFileName, defaultConfigurationTable)
    -- Try to load configuration file
    local fileContent = readAll("/etc/" .. configFileName)
    -- Fill in defaults.
    local loadedConfigurationTable = defaultConfigurationTable
    if fileContent then
        loadedConfigurationTable = json.decode(fileContent)
    end
    -- Generate config file if it didn't exist.
    if not filesystem.exists("/etc/" .. configFileName) then
        local rootDirectory = filesystem.get("/")
        if rootDirectory and not rootDirectory.isReadOnly() then
            if filesystem.makeDirectory then filesystem.makeDirectory("/etc") end
            local f = io.open("/etc/" .. configFileName, "w")
            if f then
                f:write(json.encode(loadedConfigurationTable))
                f:close()
            end
        end
        loadedConfigurationTable = defaultConfigurationTable
    end
    return loadedConfigurationTable
end


--[[
    TODO
 ]]
---
-- Saves given config by overwriting/creating given file
-- Returns saved config
function fileconfig.saveConfig(configFile, configurationTable)
    if configurationTable then
        local root = filesystem.get("/")
        if root and not root.isReadOnly() then
            filesystem.makeDirectory("/etc")
            local f = io.open("/etc/" .. configFile, "w")
            if f then
                f:write(json.encode(configurationTable))
                f:close()
            end
        end
    end
    return configurationTable
end

-------------------------------------- Library ---------------------------------------------

return fileconfig
