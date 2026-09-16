--!strict
--[[
    @author nat
    @date 14-09-26

    Player's Server Session object
]]
local ServerSession = {}
ServerSession.__index = ServerSession

--Modules
local ProfileStore = require("@game/ServerScriptService/ServerPackages/ProfileStore")
local Value = require("./Value")

--Types
export type ServerSessionData<T> = {
    profile: ProfileStore.Profile<T>,
    player: Player,
    data: Value.Value<T>,
}

export type Session<T> = setmetatable<ServerSessionData<T>, typeof(ServerSession)>

--Constructor
function ServerSession.new<T>(profile: ProfileStore.Profile<T>, player: Player): Session<T>
    local data: ServerSessionData<T> = {
        profile = profile,
        player = player,
        data = Value.new(profile.Data), 
    }
    return setmetatable(data, ServerSession)
end

return ServerSession