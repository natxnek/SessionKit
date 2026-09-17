--!strict
--[[
    @author nat
    @date 14-09-26

    Server version of session kit
]]
local SessionKitClient = ({} :: any) :: SessionKitClientPrivate<any>

--Services
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

--Require guard
if not RunService:IsClient() then
    return {}
end

--Modules
local Value = require("../classes/Value")
local SessionKitNamespace = require("../networking/SessionKitNamespace")
local SessionKitTypes = require("../shared/SessionKitTypes")

--Types
export type SessionKitClientModule<T> = {
    read data: Value.Value<T>
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
    SessionKitNamespace.packets.SetValue.listen(function(packet)
        if not SessionKitClient._initialDataLoaded then
            return
        end

        local target = resolvePath(packet.path)
        local decodedValue = HttpService:JSONDecode(packet.value :: any)
        target(decodedValue)
    end)

    SessionKitNamespace.packets.ArrayInsert.listen(function(packet)
        if not SessionKitClient._initialDataLoaded then
            return
        end

        local target = resolvePath(packet.path)
        local decodedValue = HttpService:JSONDecode(packet.value :: any)
        target.Insert(decodedValue, packet.index)
    end)

    SessionKitNamespace.packets.ArrayRemove.listen(function(packet)
        if not SessionKitClient._initialDataLoaded then
            return
        end

        local target = resolvePath(packet.path)
        target.Remove(packet.index)
    end)

    --spent 2h debugging why this yielded even though the debug print after it ran,
    --turns out bytenet coroutine.yields after invoke for some reason. wrapped it in task.spawn and it works. i hate myself
    task.spawn(function()
        local fetchedData = SessionKitNamespace.queries.GetData.invoke(nil)
        if fetchedData then
            SessionKitClient.data(fetchedData)
        end
        SessionKitClient._initialDataLoaded = true
    end)

    return SessionKitClient
end

return SessionKitClient