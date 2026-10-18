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
const ProfileStore = require("../../ProfileStore")
const Value = require("../Value")
const PacketsServer = require("../server/PacketsServer")
const SessionKitTypes = require("../shared/SessionKitTypes")

--Types
export type ServerSessionData<T> = {
    profile: ProfileStore.Profile<T>,
    player: Player,
    data: Value.Value<T>,

    hasLoaded: boolean,
}

export type Session<T> = setmetatable<ServerSessionData<T>, typeof(ServerSession)>

const function getDefaultReplicationSink(player: Player, scheme: SessionKitTypes.SessionKitDataScheme?): Value.ReplicateSink
    return function(path, operation, a, b)
        local root = path[1]
        if scheme and root ~= nil then
            local entry = scheme[root]
            if entry and entry.replicateOnChange == false then
                return
            end
        end

        local encodedValue = HttpService:JSONEncode(a)
        if operation == "Set" then
            PacketsServer.SessionKit.SetValue.Fire(player, path, encodedValue)
        elseif operation == "Insert" then
            PacketsServer.SessionKit.ArrayInsert.Fire(player, path, encodedValue, b :: number)
        elseif operation == "Remove" then
            PacketsServer.SessionKit.ArrayRemove.Fire(player, path, b :: number)
        end
    end
end

--Constructor
function ServerSession.new<T>(profile: ProfileStore.Profile<T>, player: Player, scheme: SessionKitTypes.SessionKitDataScheme?): Session<T>
    local data: ServerSessionData<T> = {
        profile = profile,
        player = player,
        data = Value.new(profile.Data, nil, nil, getDefaultReplicationSink(player, scheme)),
        hasLoaded = false,
    }
    return setmetatable(data, ServerSession)
end

return ServerSession