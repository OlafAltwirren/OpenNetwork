--
-- Created by IntelliJ IDEA.
-- User: FinFarenath
-- Date: 08.07.2018
-- Time: 14:20
-- To change this template use File | Settings | File Templates.
--

-- local filesystem = require("filesystem")

local logging = {}

logging.core = {}
logging.core.initialized = false

logging.core.loggers = {}

function logging.core.init()
    if logging.core.initialized then
        return
    else
        -- filesystem.rename("/log.txt", "/log.old")
        logging.core.initialized = true
        logging.core.logFile = io.open("/tmp/log.txt", "w")
    end
end

function logging.getLogger(namedLogger)
    logging.core.init()
    logging.core.loggers[namedLogger] = {
        loggerName = namedLogger,
        log = function(level, message)
            logging.core.logFile:write(os.date() .. " - " .. level .. " - " .. namedLogger .. " - " .. message .. "\n")
            logging.core.logFile:flush()
        end
    }
    -- Add proxies
    logging.core.loggers[namedLogger].trace = function(message)
        logging.core.loggers[namedLogger].log("trace", message)
    end
    logging.core.loggers[namedLogger].debug = function(message)
        logging.core.loggers[namedLogger].log("debug", message)
    end
    logging.core.loggers[namedLogger].info = function(message)
        logging.core.loggers[namedLogger].log("info", message)
    end
    logging.core.loggers[namedLogger].warn = function(message)
        logging.core.loggers[namedLogger].log("warn", message)
    end
    logging.core.loggers[namedLogger].error = function(message)
        logging.core.loggers[namedLogger].log("error", message)
        error(message)
    end

    return logging.core.loggers[namedLogger]
end


return logging
