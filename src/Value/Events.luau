--!strict
--[[
    @author nat
    @date 07-10-26

    Holds all event functions and handlers
]]
local Events = {}

--Modules
const Log = require("../shared/Log")
const Validate = require("../shared/Validate")
const Constants = require("./Constants")
const getPath = require("./getPath")

--Types
type Entry = { fn: (...any) -> ...any }

--Returns the error traceback
local function traceHandler(err: any): string
    return debug.traceback(tostring(err), 2)
end

--Spawns every callback safely
local function dispatch(entries: { Entry }?, label: string, ...: any)
    if not entries or #entries == 0 then
        return
    end

    --clone: a callback can unsubscribe itself mid-loop (task.spawn runs synchronously),
    --which would make table.remove skip the next entry
    for _, entry in table.clone(entries) do
        task.spawn(function(...)
            local ok, err = xpcall(entry.fn, traceHandler, ...)
            if not ok then
                warn(`[SessionKit] {label} callback errored:\n{err}`)
            end
        end, ...)
    end
end

--Registers a callback under listKey, returns an unsubscribe function
function Events.register(value: any, listKey: string, callback: (...any) -> ...any): () -> ()
    if typeof(callback) ~= "function" then
        Log.error(
            "E_BAD_CALLBACK",
            `{Validate.pathToString(getPath(value))}: a listener must be a function, got {typeof(callback)}`,
            3
        )
    end
    
    local entries = rawget(value, listKey)
    if not entries then
        entries = {}
        rawset(value, listKey, entries)
    end

    --wrap in a unique entry so registering the same function twice
    --doesn't make unsubscribe remove the wrong one
    local entry: Entry = { fn = callback }
    table.insert(entries, entry)

    return function()
        local current = rawget(value, listKey)
        local index = current and table.find(current, entry)
        if index then
            table.remove(current, index)
        end
    end
end

--True if this Value or anything under it has a change listener
function Events.hasListeners(value: any, memo: { [any]: boolean }?): boolean
    local cache = memo or {}
    local cached = cache[value]
    if cached ~= nil then
        return cached
    end

    local result = false
    local own = rawget(value, Constants.CHANGED_KEY)
    if own and #own > 0 then
        result = true
    else
        local children = rawget(value, Constants.CHILDREN_KEY)
        if children then
            for _, child in children do
                if Events.hasListeners(child, cache) then
                    result = true
                    break
                end
            end
        end
    end

    cache[value] = result
    return result
end

--Fires OnChange for the Value, its listening descendants, then its ancestors
function Events.fireChanged(value: any, oldValue: any)
    local memo = {} --one hasListeners pass per fire instead of per level

    local function fireDeep(v: any, old: any)
        local new = v()
        dispatch(rawget(v, Constants.CHANGED_KEY), "OnChange", new, old)

        local children = rawget(v, Constants.CHILDREN_KEY)
        if children and typeof(old) == "table" and old ~= new then
            for key, child in children do
                if Events.hasListeners(child, memo) then
                    fireDeep(child, old[key])
                end
            end
        end
    end

    fireDeep(value, oldValue)

    --ancestors: their table was mutated in place, so we don't have a real "old" for them.
    --pass nil instead of lying with the child's old value
    local ancestor = rawget(value, Constants.PARENT_KEY)
    while ancestor do
        dispatch(rawget(ancestor, Constants.CHANGED_KEY) :: any, "OnChange", (ancestor :: any)(), nil)
        ancestor = rawget(ancestor, Constants.PARENT_KEY)
    end
end

--OnKeyAdded / OnKeyRemoved
function Events.fireKey(owner: any, listKey: string, key: any, valueAtKey: any)
    dispatch(rawget(owner, listKey), listKey, key, valueAtKey)
end

--Array events (called from Array.luau after the mutation)
function Events.fireArray(value: any, listKey: string, item: any, index: number)
    dispatch(rawget(value, listKey), listKey, item, index)
end

--Factories for VALUE_FUNCTIONAL_KEYS: value -> (callback) -> unsubscribe
function Events.OnChange(value: any)
    return function(callback, ignoreInitialData: boolean?)
        local unsubscribe = Events.register(value, Constants.CHANGED_KEY, callback)

        if ignoreInitialData ~= true then
            local current = value()
            if current ~= nil then
                dispatch({ { fn = callback } }, "OnChange", current, nil)
            end
        end

        return unsubscribe
    end
end

function Events.OnInsert(value: any)
    return function(callback) return Events.register(value, Constants.ARRAY_INSERTED_KEY, callback) end
end
function Events.OnRemove(value: any)
    return function(callback) return Events.register(value, Constants.ARRAY_REMOVED_KEY, callback) end
end
function Events.OnKeyAdded(value: any)
    return function(callback) return Events.register(value, Constants.KEY_ADDED_KEY, callback) end
end
function Events.OnKeyRemoved(value: any)
    return function(callback) return Events.register(value, Constants.KEY_REMOVED_KEY, callback) end
end

return Events