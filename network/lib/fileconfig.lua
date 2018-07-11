fileconfig = {}
local filesystem = require("filesystem")
local logger = require("logging").getLogger("config")
local json = require("json")

--[[
Loads configuration.<br>
If file doesn't exist, creates new one with given defaultCfg<br>
<p><b>Example defaultCfg:</b></p>
<code>
  defaultCfg = {
    cfgString = "string value",
    cfgArray = {"array0 value0", "array0 value1"}, {"array1 value0", "array1 value1"}
  }
</code>
</p>
Variables in configuration can be then read by they names:<p>
<code>
config = require("config")
conf = config.loadConfig("filename.cfg", defaultCfg)
print(conf["cfgString"])
</code>
<p>Results:<br>
<i>string value</i>
</p>
--]]


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

--[[
    TODO
 ]]
function fileconfig.loadConfig(configFileName, defaultConfigurationTable)
    -- Try to load configuration file
    logger.log("Loading from file /etc/"..configFileName)
    local fileContent = readAll("/etc/" .. configFileName)
    -- Fill in defaults.
    local loadedConfigurationTable = defaultConfigurationTable
    if fileContent then
        logger.log("Got content at "..fileContent)
        loadedConfigurationTable = json.decode(fileContent)
        logger.log("Decoded from JSON as "..loadedConfigurationTable)
    end
    -- Generate config file if it didn't exist.
    if not filesystem.exists("/etc/" .. configFileName) then
        local rootDirectory = filesystem.get("/")
        if rootDirectory and not rootDirectory.isReadOnly() then
            filesystem.makeDirectory("/etc")
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

return fileconfig
