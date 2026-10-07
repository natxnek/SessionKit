--!strict
--[[
    @author nat
    @date 14-09-26

    Server version of session kit
]]
const SessionKitClient = ({} :: any) :: SessionKitClientPrivate<any>

--Services
const HttpService = game:GetService("HttpService")
const RunService = game:GetService("RunService")

--Require guard
if not RunService:IsClient() then
    return {}
end

--Modules
const Value = require("../Value")
const SessionKitTypes = require("../shared/SessionKitTypes")
const PacketsClient = require("./PacketsClient")

--Types
export type SessionKitClientModule<T> = {
    read data: Value.Value<T>,
    isInitialDataLoaded: () -> boolean,
}

export type SessionKitClientPrivate<T> = SessionKitClientModule<T> & {
    _loaded: boolean,
    _initialDataLoaded: boolean,

    --functions
    initialize: <T>(template: T, options: SessionKitTypes.SessionKitOptions?) -> SessionKitClientModule<T>,
}

const function resolvePath(path: { string }): Value.Value<any>
    local current: Value.Value<any> = SessionKitClient.data
    for _, key in path do
        if current() == nil then
            current({})
        end
        current = current[key]
    end
    return current
end

function SessionKitClient.isInitialDataLoaded()
    return SessionKitClient._initialDataLoaded
end

--Initializes the session kit client module
function SessionKitClient.initialize<T>(template, options)
    if SessionKitClient._loaded then
        return SessionKitClient
    end
    SessionKitClient._loaded = true
    SessionKitClient._initialDataLoaded = false

    --wtf is happening to the solver recently bruh, how tf is that not an error
    SessionKitClient.data = Value.new<<T>>(template)

    --any packet that arrives before the initial snapshot lands is discarded
    PacketsClient.SessionKit.SetValue.On(function(path, value)
        if not SessionKitClient._initialDataLoaded then
            return
        end

        local target = resolvePath(path)
        local decodedValue = HttpService:JSONDecode(value)
        target(decodedValue)
    end)

    PacketsClient.SessionKit.ArrayInsert.On(function(path, value, index)
        if not SessionKitClient._initialDataLoaded then
            return
        end

        local target = resolvePath(path)
        local decodedValue = HttpService:JSONDecode(value)
        target.Insert(decodedValue, index)
    end)

    PacketsClient.SessionKit.ArrayRemove.On(function(path, index)
        if not SessionKitClient._initialDataLoaded then
            return
        end

        local target = resolvePath(path)
        target.Remove(index)
    end)

    task.spawn(function()
        local fetchedData: string? = nil
        
        -- Retry until valid snapshot payload arrives
        while not fetchedData do
            fetchedData = PacketsClient.SessionKit.GetData.Invoke(nil)
            if not fetchedData then
                task.wait(.5)
            end
        end

        local decodedData = HttpService:JSONDecode(fetchedData or "{}")
        SessionKitClient.data(decodedData)
        
        SessionKitClient._initialDataLoaded = true
    end)

    return SessionKitClient
end

return SessionKitClient