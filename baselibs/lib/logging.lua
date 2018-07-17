--[[
    Library logging

    Provides basic and complex logging to a log facility. This can be a file as well as a configurable log level at
    minimum.

    Available log levels are in the following order TRACE, DEBUG, INFO, WARN, ERROR. Depending on the log level given
    and the configured loglevel the log line will be written out to the configured file.

    The configuration will be read from a JSON configuration file from "/etc/logging.json". If that file doesn't exist,
    it will be created on first installation and startup for you to edit later.

    Requires:
        - event
        - fileconfig > 0.1
        - OpenComputers > 1.7
        - OpenOS > 1.7

    Author:
        Olaf Altwirren ( olaf.altwirren@airflowrental.de )
 ]]

-------------------------------------- Configuration and Structures ---------------------------------------------

local fileconfig = require("fileconfig")
local event = require("event")

local loggerConfiguration = {
    logfile = "/tmp/messages.log",
    rootlevel = "debug",
    loglevels = {
        network = {
            loglevel = "info",
            logfile = "/tmp/network.log"
        },
        icmp = {
            loglevel = "info",
            logfile = "/tmp/network.log"
        },
        inp = {
            loglevel = "info",
            logfile = "/tmp/network.log"
        },
        udp = {
            loglevel = "info",
            logfile = "/tmp/network.log"
        },
        tcp = {
            loglevel = "info",
            logfile = "/tmp/network.log"
        }
    }
}

-- prototype
local logging = {
    _version = "0.1",
    core = {
        loggers = {}
    },
    loggers = {},
    logfiles = {}, -- filehandles by namedLogger-name
    config = nil
}

-------------------------------------- Internal Helpers and Functions ---------------------------------------------

local logLevels = {}
logLevels["trace"] = 1
logLevels["debug"] = 2
logLevels["info"] = 3
logLevels["warn"] = 4
logLevels["error"] = 5

local logLevelNames = {}
logLevelNames[1] = "trace"
logLevelNames[2] = "debug"
logLevelNames[3] = "info"
logLevelNames[4] = "warn"
logLevelNames[5] = "error"

local function getMinLogLevel(level1, level2)
    local numberLevel1 = logLevels[level1]
    local numberLevel2 = logLevels[level2]
    local numberLevelMin = math.min(numberLevel1, numberLevel2)
    return logLevelNames[numberLevelMin]
end

local function getMaxLogLevel(level1, level2)
    local numberLevel1 = logLevels[level1]
    local numberLevel2 = logLevels[level2]
    local numberLevelMin = math.max(numberLevel1, numberLevel2)
    return logLevelNames[numberLevelMin]
end

-------------------------------------- API Functions and Methods ---------------------------------------------

--[[
    Initialize the logging framework
 ]]
function logging.core.init(namedLogger)
    -- Initialize globally if not done already
    if not logging.config then
        logging.config = fileconfig.loadConfig("logging.json", loggerConfiguration)
        -- start timer
        event.timer(30, function()
            for logfileName, logfileHandle in pairs(logging.logfiles) do
                logfileHandle:flush()
            end
        end, math.huge)
    end

    if logging.core.loggers[namedLogger] then
        return
    else
        -- Get namedLogger filename
        local logfileName = logging.config.logfile -- default
        if logging.config.loglevels[namedLogger] then
            logfileName = logging.config.loglevels[namedLogger].logfile
        end
        logging.core.loggers[namedLogger] = {
            loggerName = namedLogger,
            filename = logfileName
        }

        -- Set loglevel or use default
        local logLevel = logging.config.rootlevel -- default
        if logging.config.loglevels[namedLogger] and logging.config.loglevels[namedLogger].loglevel then
            logLevel = getMaxLogLevel(logLevel, logging.config.loglevels[namedLogger].loglevel)
        end
        logging.core.loggers[namedLogger].loglevel = logLevel

        -- Open logfile if not already open
        if not logging.logfiles[logfileName] then
            logging.logfiles[logfileName] = io.open(logfileName, "w")
        end
    end
end

--[[
    Generates a logger proxy for the given logger name.
 ]]
function logging.getLogger(namedLogger)
    -- Try to initialize if not already done
    logging.core.init(namedLogger)

    -- Create the logger facility for the name
    logging.core.loggers[namedLogger] = {
        log = function(level, message)
            if logLevels[level] >= logLevels[logging.core.loggers[namedLogger].loglevel] then
                logging.logfiles[logging.core.loggers[namedLogger].filename]:write(os.date() .. " - " .. level .. " - " .. namedLogger .. " - " .. message .. "\n")
                -- WIll be done by timer logging.core.logFile:flush()
            end
        end
    }

    -- Add proxy for TRACE
    if logLevels[logging.core.loggers[namedLogger].loglevel] > 0 then
        logging.core.loggers[namedLogger].trace = function(message)
            logging.core.loggers[namedLogger].log("trace", message)
        end
    else
        logging.core.loggers[namedLogger].trace = function() end
    end

    -- Add proxy for DEBUG
    if logLevels[logging.core.loggers[namedLogger].loglevel] > 1 then
        logging.core.loggers[namedLogger].debug = function(message)
            logging.core.loggers[namedLogger].log("debug", message)
        end
    else
        logging.core.loggers[namedLogger].debug = function() end
    end

    -- Add proxy for INFO
    if logLevels[logging.core.loggers[namedLogger].loglevel] > 2 then
        logging.core.loggers[namedLogger].info = function(message)
            logging.core.loggers[namedLogger].log("info", message)
        end
    else
        logging.core.loggers[namedLogger].info = function() end
    end

    -- Add proxy for WARN
    if logLevels[logging.core.loggers[namedLogger].loglevel] > 3 then
        logging.core.loggers[namedLogger].warn = function(message)
            logging.core.loggers[namedLogger].log("warn", message)
        end
    else
        logging.core.loggers[namedLogger].warn = function() end
    end

    -- Add proxy for ERROR
    if logLevels[logging.core.loggers[namedLogger].loglevel] > 4 then
        logging.core.loggers[namedLogger].error = function(message)
            logging.core.loggers[namedLogger].log("error", message)
            error(message)
        end
    else
        logging.core.loggers[namedLogger].error = function() end
    end

    return logging.core.loggers[namedLogger]
end

-------------------------------------- Library ---------------------------------------------

return logging
