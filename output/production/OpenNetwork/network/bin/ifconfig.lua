local libLayer1network = require("libLayer1network")
local computer = require("computer")
local args = {...}

local function align(txt)return txt .. ("        "):sub(#txt+1)end

if #args < 1 then
    print("Network interfaces:")
    local interfaces = libLayer1network.stp.getInterfaces()
    for interfaceUUID, infoStruct in pairs(interfaces) do
        print(align(infoStruct.name).."Link encap:"..infoStruct.type)
        print("        HWaddr "..interfaceUUID)
        local pktIn, pktOut, bytesIn, bytesOut = infoStruct.driver.driver.info(interfaceUUID)
        print("        RX packets:"..tostring(pktIn))
        print("        TX packets:"..tostring(pktOut))
        print("        RX bytes:"..tostring(bytesIn).."  TX bytes:"..tostring(bytesOut))
    end
elseif args[1] == "bind" and args[2] then
    -- TODO print("Address attached")
    -- TODO network.ip.bind(args[2])
else
   print("Usage:")
   print(" ifconfig - view network summary")
   print(" TODO ifconfig bind [addr] - 'attach' addnitional address to computer")
end
