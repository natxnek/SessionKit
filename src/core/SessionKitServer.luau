--!strict
--[[
    @author nat
    @date 14-09-26

    Server version of session kit
]]
local SessionKitServer = {} :: SessionKitServerPrivate<any>

--Services
const HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

--Require guard
if not RunService:IsServer() then
    return {}
end

--Modules
const ProfileStore = require("../../ProfileStore")
const Signal = require("../../Signal")
local ServerSession = require("../classes/ServerSession")
const PacketsServer = require("../networking/PacketsServer")
local SessionKitTypes = require("../shared/SessionKitTypes")

--Types
export type Session<T> = ServerSession.Session<T>
export type SessionCallback<T> = (session: Session<T>) -> ()
export type SessionKitServerModule<T> = {
    --Registers a callback fired whenever a session loads
    --Returns a disconnect function
    onSessionOpen: (callback: SessionCallback<T>) -> (() -> ()),

    --Registers a callback fired whenever a session closes and player is leaving
    --Returns a disconnect function
    onSessionClose: (callback: SessionCallback<T>) -> (() -> ()),

    --Tries to fetch a session and yields until it finds one (max 15s)
    awaitGetSession: (player: Player) -> Session<T>?,
} & { [Player]: Session<T> } --Direct session querying (SessionKitServer[player]) can be nil

export type SessionKitServerPrivate<T> = SessionKitServerModule<T> & {
    _loaded: boolean,
    _store: ProfileStore.ProfileStore<T>,
    _sessions: { [Player]: Session<T> },

    _connectedCallbacks: {
        open: { (any) -> () },
        close: { (any) -> () },
    },

    _awaitSignals: { [Player]: Signal.Signal<Session<T>> },
    
    --functions
    initialize: (template: T, options: SessionKitTypes.SessionKitOptions?) -> SessionKitServerModule<T>,
}

--Removes the player profile and closes the profile's session
local function removePlayer(player: Player)
    local optionalSession = SessionKitServer._sessions and SessionKitServer._sessions[player]
    if not optionalSession then
        return
    end

    --something's bugging out and session is nil lol
    local session = ((optionalSession :: any) :: ServerSession.Session<any>)
    SessionKitServer._sessions[player] = nil

    for _, callback in SessionKitServer._connectedCallbacks.close do
        task.spawn(callback, session)
    end

    if session.profile then
        session.profile:EndSession()
    end

    if SessionKitServer._awaitSignals[player] then
        SessionKitServer._awaitSignals[player]:Destroy()
        SessionKitServer._awaitSignals[player] = nil
    end
end

--Loads the player's session
local function loadPlayer(player: Player)
    if SessionKitServer._sessions and SessionKitServer._sessions[player] then
        return
    end

    local profile = SessionKitServer._store:StartSessionAsync(`{player.UserId}`, {})
    if not profile then
        warn(`[SessionKit] Failed to load profile for {player.Name}. Kicking player`)
        player:Kick("Failed to load data")
        return
    end

    profile:Reconcile()
    profile:AddUserId(player.UserId)

    profile.OnSessionEnd:Connect(function()
        if SessionKitServer._sessions[player] then
            removePlayer(player)
        end
    end)

    local serverSession = ServerSession.new<<any>>(profile, player)
    SessionKitServer._sessions[player] = serverSession

    for _, callback in SessionKitServer._connectedCallbacks.open do
        task.spawn(callback, serverSession)
    end

    local awaitSignal = SessionKitServer._awaitSignals[player]
    if awaitSignal then
        awaitSignal:Fire(serverSession)
        SessionKitServer._awaitSignals[player] = nil
    end
end

--Registers a session open callback
function SessionKitServer.onSessionOpen(callback)
    table.insert(SessionKitServer._connectedCallbacks.open, callback)
    return function()
        local index = table.find(SessionKitServer._connectedCallbacks.open, callback)
        if index then
            table.remove(SessionKitServer._connectedCallbacks.open, index)
        end
    end
end

--Registers a session close callback
function SessionKitServer.onSessionClose(callback)
    table.insert(SessionKitServer._connectedCallbacks.close, callback)
    return function()
        local index = table.find(SessionKitServer._connectedCallbacks.close, callback)
        if index then
            table.remove(SessionKitServer._connectedCallbacks.close, index)
        end
    end
end

--Synchronously gets the session, awaits if session hasn't been loaded yet
function SessionKitServer.awaitGetSession<T>(player)
    if SessionKitServer._sessions[player] then
        return SessionKitServer._sessions[player]
    end

    local awaitSignal = (SessionKitServer._awaitSignals[player] or Signal.new()) :: Signal.Signal<Session<T>>
    SessionKitServer._awaitSignals[player] = awaitSignal

    return SessionKitServer._sessions[player] or awaitSignal:Wait() --double check, idk why, this can probably be removed
end

--Initializes the session kit server module
function SessionKitServer.initialize(template, options)
    if SessionKitServer._loaded then
        return SessionKitServer
    end
    SessionKitServer._loaded = true

    SessionKitServer._sessions = {}
    SessionKitServer._awaitSignals = {}
    SessionKitServer._connectedCallbacks = {
        open = {},
        close = {}
    }

    SessionKitServer._store = ProfileStore.New((options and options.storeName) and options.storeName or "default", template)

    Players.PlayerAdded:Connect(loadPlayer)
    Players.PlayerRemoving:Connect(removePlayer)

    for _, player in Players:GetPlayers() do
        task.spawn(loadPlayer, player)
    end

    PacketsServer.SessionKit.GetData.On(function(player)
        if not player then
            return nil
        end
        
        local nillableSession = SessionKitServer._sessions[player]
        if not nillableSession then
            return nil
        end

        --what the fuck is wrong with my intellisense, like the autocomplete is empty for the earlier session bruh
        local session = (nillableSession :: any) :: Session<any>
        return HttpService:JSONEncode(session.profile.Data)
    end)

    setmetatable(SessionKitServer, {
        __index = function(self, key): Session<any>?
            if typeof(key) == "Instance" and key:IsA("Player") then
                local sessions = rawget(self, "_sessions") :: { [Player]: Session<any> }
                if sessions then
                    return sessions[key]
                end
            end
            return nil
        end,
    })

    return SessionKitServer :: any
end

return SessionKitServer