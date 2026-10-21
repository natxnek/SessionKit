--!strict
--[[
    @author nat
    @date 14-09-26

    Server version of session kit
]]
const SessionKitServer = {} :: SessionKitServerPrivate<any>

--Services
const HttpService = game:GetService("HttpService")
const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

--Require guard
if not RunService:IsServer() then
    return {}
end

--Modules
const ProfileStore = require("../../ProfileStore") --for prod
-- const ProfileStore = require("@game/ServerScriptService/ServerPackages/ProfileStore") --for dev
const Signal = require("../../Signal") --for prod
-- const Signal = require("../../Packages/Signal") --for dev
const SessionKitTypes = require("../shared/SessionKitTypes")
const PacketsServer = require("./PacketsServer")
const ServerSession = require("./ServerSession")

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

    --Tries to fetch a session and yields until it finds one (max 5s)
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

    _awaitSignals: { [Player]: Signal.Signal<Session<T>?> },
    
    _dataScheme: SessionKitTypes.SessionKitDataScheme<{} & T>?,

    --functions
    initialize: (template: T, options: SessionKitTypes.SessionKitOptions<{} & T>?) -> SessionKitServerModule<T>,
}

--Returns the encoded json data from the given data table
--omits the keys whose data scheme entry strictly says to not replicate initial data
const function getEncodedInitialData(data: { [any]: any }): string
    if typeof(data) ~= 'table' then
        return "{}"
    end

    local filteredData: { [any]: any } = {}
    for key, value in data do
        local scheme = SessionKitServer._dataScheme :: SessionKitTypes.SessionKitDataScheme<{}>
        if scheme then
            local entry = (scheme :: { [any]: any })[key] :: SessionKitTypes.SessionKitDataSchemeEntry
            if entry and entry.replicateInitialValue == false then
                continue
            end
        end

       filteredData[key] = value
    end

    return HttpService:JSONEncode(filteredData)
end

--Runs the session closed callbacks
--this looks horrible
const function runCloseCallbacks(session: Session<any>, timeout: number)
    const callbacks = table.clone(SessionKitServer._connectedCallbacks.close)
    local pending = #callbacks
    if pending == 0 then
        return
    end

    const thread = coroutine.running()
    local done = false

    local function finish()
        if done then
            return
        end
        done = true
        task.spawn(thread)
    end

    for _, callback in callbacks do
        task.spawn(function()
            local ok, err = pcall(callback, session)
            if not ok then
                warn(`[SessionKit] Close callback errored: {err}`)
            end
            pending -= 1
            if pending == 0 then
                finish()
            end
        end)
    end

    task.delay(timeout, finish)
    coroutine.yield()
end

--Removes the player profile and closes the profile's session
const function removePlayer(player: Player)
    local awaitSignal = SessionKitServer._awaitSignals[player]
    if awaitSignal then
        SessionKitServer._awaitSignals[player] = nil
        awaitSignal:Fire(nil)
        awaitSignal:Destroy()
    end

    local session = SessionKitServer._sessions and SessionKitServer._sessions[player]
    if session == nil then
        return
    end

    SessionKitServer._sessions[player] = nil
    runCloseCallbacks(session, 10)

    if session.profile then
        session.profile:EndSession()
    end

    if SessionKitServer._awaitSignals[player] then
        SessionKitServer._awaitSignals[player]:Destroy()
        SessionKitServer._awaitSignals[player] = nil
    end
end

--Loads the player's session
const function loadPlayer<T>(player: Player)
    if SessionKitServer._sessions and SessionKitServer._sessions[player] then
        return
    end

    local profile = SessionKitServer._store:StartSessionAsync(`{player.UserId}`, {})
    if not profile then
        warn(`[SessionKit] Failed to load profile for {player.Name}. Kicking player`)
        player:Kick("Failed to load data")
        return
    end

    if player.Parent ~= game:GetService("Players") then
        profile:EndSession()
        return
    end

    profile:Reconcile()
    profile:AddUserId(player.UserId)

    profile.OnSessionEnd:Connect(function()
        if SessionKitServer._sessions[player] then
            removePlayer(player)
        end
        player:Kick("Your session has ended")
    end)

    local serverSession = ServerSession.new<<T>>(profile, player, SessionKitServer._dataScheme)
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
    local session = SessionKitServer._sessions[player]
    if session then
        return session
    end
    if player.Parent ~= Players then
        return nil
    end

    local awaitSignal = SessionKitServer._awaitSignals[player]
    if not awaitSignal then
        local newSignal = Signal.new()
        awaitSignal = newSignal
        SessionKitServer._awaitSignals[player] = awaitSignal

        task.delay(5, function()
            if SessionKitServer._awaitSignals[player] == awaitSignal then
                SessionKitServer._awaitSignals[player] = nil
                newSignal:Fire(nil)
                newSignal:Destroy()
            end
        end)
    end

    return awaitSignal:Wait()
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
    SessionKitServer._dataScheme = options and options.dataScheme

    Players.PlayerAdded:Connect(loadPlayer)
    Players.PlayerRemoving:Connect(removePlayer)

    for _, player in Players:GetPlayers() do
        task.spawn(loadPlayer, player)
    end

    PacketsServer.SessionKit.GetData.On(function(player)
        if not player then
            return nil
        end
        
        local session = SessionKitServer.awaitGetSession(player)
        if session == nil then --idk why but `not session` makes the session nil later
            return nil
        end

        return getEncodedInitialData(session.profile.Data)
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