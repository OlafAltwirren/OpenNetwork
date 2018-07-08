-- keep all links to the dirver for the networkLayer1.lua
local driver = {}

-- public functions
local libLayer1network = {}
local internal = {}

------------
-- Core communication
libLayer1network.core = {}

function libLayer1network.core.setCallback(name, fn)
    driver[name] = fn
end

function libLayer1network.core.lockCore()
    libLayer1network.core = nil
end

------------


------------
-- STP

libLayer1network.stp = {}
internal.stp = {}


function libLayer1network.stp.getTopologyTable()
    if not driver.getTopologyTable then
        print("Layer1 Network demon not loaded.")
        return {}
    else
        return driver.getTopologyTable()
    end
end

function libLayer1network.stp.getInterfaces()
    if not driver.getTopologyTable then
        print("Layer1 Network demon not loaded.")
        return {}
    else
        return driver.getInterfaces()
    end
end

------------

return libLayer1network