--
-- Created by IntelliJ IDEA.
-- User: FinFarenath
-- Date: 08.07.2018
-- Time: 14:20
-- To change this template use File | Settings | File Templates.
--

local filesystem = require("filesystem")

local logging = {}

logging.core = {}
logging.core.initialized = false

logging.core.loggers = {}

function logging.core.init()
    if logging.core.initialied then
        return
    end
    filesystem.rename("/log.txt", "/log.old")
    logging.core.logFile = io.open("/log.txt", "w")
end

function logging.getLogger(namedLogger)
    logging.core.init()
    logging.core.loggers[namedLogger] = {
        loggerName = namedLogger,
        log = function(message)
            logging.core.logFile:write(os.date().." - "..namedLogger.." - "..message.."\n")
            logging.core.logFile:flush()
        end
    }
    return logging.core.loggers[namedLogger]
end


return logging