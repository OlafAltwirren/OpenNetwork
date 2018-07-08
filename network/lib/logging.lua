--
-- Created by IntelliJ IDEA.
-- User: FinFarenath
-- Date: 08.07.2018
-- Time: 14:20
-- To change this template use File | Settings | File Templates.
--



local logging = {}

logging.core = {}
logging.core.initialized = false

function logging.core.init()
    if logging.core.initialied then
        return
    end
    logging.core.logFile = io.open("/log.txt", "a")
end

function logging.getLogger(namedLogger)
    logging.core.init()
    return logging
end

function logging.log(message)

    logging.core.logFile:write(os.time..", "..message.."\n")
    logging.core.logFile:flush()
end

return logging