libconfig = {}
local filesystem = require("filesystem")

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
function libconfig.loadConfig(configFileName, defaultConfigurationTable)
    -- Try to load user settings.
    local loadedConfigurationTable = {}
    local configHandle = loadfile("/etc/" .. configFileName, nil, loadedConfigurationTable)
    if configHandle then
        pcall(configHandle)
    end
    -- Fill in defaults.
    loadedConfigurationTable = loadedConfigurationTable or defaultConfigurationTable
    -- Generate config file if it didn't exist.
    if not configHandle then
        local rootDirectory = filesystem.get("/")
        if rootDirectory and not rootDirectory.isReadOnly() then
            filesystem.makeDirectory("/etc")
            local f = io.open("/etc/" .. configFileName, "w")
            if f then
                local serialization = require("serialization")
                for k, v in pairs(defaultConfigurationTable) do
                    f:write(k .. "=" .. tostring(serialization.serialize(v, math.huge)) .. "\n")
                end
                f:close()
            end
        end
        loadedConfigurationTable = defaultConfigurationTable
    end
    return loadedConfigurationTable
end

---
-- Saves given config by overwriting/creating given file
-- Returns saved config
function libconfig.saveConfig(configFile, config)
    if config then
        local root = filesystem.get("/")
        if root and not root.isReadOnly() then
            filesystem.makeDirectory("/etc")
            local f = io.open("/etc/" .. configFile, "w")
            if f then
                local serialization = require("serialization")
                for k, v in pairs(config) do
                    f:write(k .. "=" .. tostring(serialization.serialize(v, math.huge)) .. "\n")
                end
                f:close()
            end
        end
    end
    return config
end

return libconfig
