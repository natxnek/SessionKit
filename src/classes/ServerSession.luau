--!strict
--[[
    @author nat
    @date 14-09-26

    Player's Server Session object
]]
local ServerSession = {}
ServerSession.__index = ServerSession

--Services
local HttpService = game:GetService("HttpService")

--Modules
local ProfileStore = require("@game/ServerScriptService/ServerPackages/ProfileStore")
local SessionKitNamespace = require("../networking/SessionKitNamespace")
local Value = require("./Value")

--Types
export type ServerSessionData<T> = {
    profile: ProfileStore.Profile<T>,
    player: Player,
    data: Value.Value<T>,

    hasLoaded: boolean,
}

export type Session<T> = setmetatable<ServerSessionData<T>, typeof(ServerSession)>

const function getDefaultReplicationSink(player: Player): Value.ReplicateSink
    --this is crazy, so bytenet doesn't allow "any" types
    --so we have to convert the a and b thing to be strings
    --so the serializer can serialize it, so we use httpservice
    --to encode it into json and decode it on the client
    return function(path, operation, a, b)
        local encodedValue = HttpService:JSONEncode(a)
        if operation == "Set" then
            SessionKitNamespace.packets.SetValue.sendTo({ path = path, value = encodedValue }, player)
        elseif operation == "Insert" then
            SessionKitNamespace.packets.ArrayInsert.sendTo({ path = path, value = encodedValue, index = b }, player)
        elseif operation == "Remove" then
            SessionKitNamespace.packets.ArrayRemove.sendTo({ path = path, index = b }, player)
        end
    end
end

--Constructor
function ServerSession.new<T>(profile: ProfileStore.Profile<T>, player: Player): Session<T>
    local data: ServerSessionData<T> = {
        profile = profile,
        player = player,
        data = Value.new(profile.Data, nil, nil, getDefaultReplicationSink(player)),
        hasLoaded = false,
    }
    return setmetatable(data, ServerSession)
end

--Manually replicates the entire data table to client
function ServerSession.replicate<T>(self: Session<T>)
    
end

return ServerSession