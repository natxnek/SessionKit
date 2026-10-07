--!strict
--[[
    @author nat
    @date 15-09-26

    Value class
]]
local Value = {}

--Modules
const Constants = require("@self/Constants")
const Events = require("@self/Events")
const getPath = require("@self/getPath")
const Validate = require("./shared/Validate")
const Log = require("./shared/Log")
const ValueTypes = require("@self/ValueTypes")

--Types
export type ValueOnChangeEvent<T> = (new: T, old: T?) -> ()
export type ValueBase<T> = ValueTypes.ValueBase<T>
export type Value<T> = ValueTypes.Value<T>
export type ReplicateSink = ValueTypes.ReplicateSink

--#region Helpers
--Throws a readable error pointing at the USER's call site.
--Only call it directly from a user-facing function (metamethod / public method), never from a
--helper, otherwise the reported line moves inside the kit
local function fail(code: string, message: string)
    Log.error(code, message, 3)
end

local function pathOf(value: any): string
    return Validate.pathToString(getPath(value))
end

--The table that currently holds this Value, resolved through the parent on EVERY access.
--Children never capture a table, so replacing a parent can't leave them pointing at an old one
local readRaw: (value: any) -> any

local function resolveContainer(value: any): any
    local parent = rawget(value, Constants.PARENT_KEY)
    if parent == nil then
        return rawget(value, Constants.CONTAINER_KEY) --root: the profile/template table
    end

    local container = readRaw(parent)
    return if typeof(container) == "table" then container else nil
end

readRaw = function(value: any): any
    local container = resolveContainer(value)
    local key = rawget(value, Constants.KEY_KEY)
    if key == nil then
        return container --root
    end
    if container == nil then
        return nil --the path doesn't exist right now, reads give nil
    end
    return container[key]
end

--Runs the sink without ever letting a replication error break the write that already happened
local function replicate(value: any, operation: "Set" | "Insert" | "Remove", a: any, b: any?)
    local sink: any = rawget(value, Constants.REPLICATE_KEY)
    if typeof(sink) ~= "function" then
        return
    end

    local ok, err = (pcall :: any)(sink, getPath(value), operation, a, b)
    if not ok then
        Log.warn(
            "E_REPLICATE_FAILED",
            `replicating {operation} on {pathOf(value)} failed, the client may be out of sync:\n{err}`
        )
    end
end
--#endregion

--#region Array operations
const function ArrayInsert(value: any)
    return function(item: any, position: number?): number
        local path = getPath(value)
        local raw = readRaw(value)

        local code, message = Validate.arrayOperation(path, raw, "Insert", position)
        if code then
            fail(code, message :: string)
        end
        if item == nil then
            fail("E_NIL_ITEM", `{Validate.pathToString(path)}.Insert: the item is nil, arrays can't hold nil`)
        end

        local insertAt = position or (#raw + 1)

        local itemPath = table.clone(path)
        table.insert(itemPath :: any, insertAt)
        local itemCode, itemMessage = Validate.value(itemPath, item)
        if itemCode then
            fail(itemCode, itemMessage :: string)
        end

        --only snapshot when someone is listening (this Value or anything under it)
        local snapshot = if Events.hasListeners(value) then table.clone(raw) else nil
        table.insert(raw, insertAt, item)

        --replicate BEFORE any callback runs: callbacks start synchronously and may write,
        --and their writes must reach the client after this one
        replicate(value, "Insert", item, insertAt)

        Events.fireChanged(value, snapshot)
        Events.fireArray(value, Constants.ARRAY_INSERTED_KEY, item, insertAt)

        return insertAt
    end
end

const function ArrayRemove(value: any)
    return function(position: number?): any
        local path = getPath(value)
        local raw = readRaw(value)

        local code, message = Validate.arrayOperation(path, raw, "Remove", position)
        if code then
            fail(code, message :: string)
        end

        if position == nil and #raw == 0 then
            return nil --removing the last item of an empty array is a no-op (no events, no replication)
        end
        local removeAt = position or #raw

        local snapshot = if Events.hasListeners(value) then table.clone(raw) else nil
        local removedItem = table.remove(raw, removeAt)

        replicate(value, "Remove", nil, removeAt)

        Events.fireChanged(value, snapshot)
        Events.fireArray(value, Constants.ARRAY_REMOVED_KEY, removedItem, removeAt)

        return removedItem
    end
end
--#endregion

--Maps method names accessible on a Value to the factory that builds them
const VALUE_FUNCTIONAL_KEYS = {
    OnChange = Events.OnChange,
    Insert = ArrayInsert,
    Remove = ArrayRemove,
    OnInsert = Events.OnInsert,
    OnRemove = Events.OnRemove,
    OnKeyAdded = Events.OnKeyAdded,
    OnKeyRemoved = Events.OnKeyRemoved,
}

local construct: (raw: any, key: string | number | nil, parent: any, replicateSink: ReplicateSink?) -> any

--#region Metamethods
--__index: method access, or child Value creation/caching for plain keys
const function onValueIndex(value: any, index: any): any
    const functionalKey = (VALUE_FUNCTIONAL_KEYS :: any)[index]
    if functionalKey then
        return (functionalKey :: any)(value)
    end

    local raw = readRaw(value)
    if typeof(raw) ~= "table" then
        fail(
            "E_NOT_TABLE",
            `can't read '{tostring(index)}' from {pathOf(value)}: it is {typeof(raw)}, not a table`
        )
    end

    local children = rawget(value, Constants.CHILDREN_KEY)
    local cached = if children then children[index] else nil
    if cached ~= nil then
        return cached
    end

    local keyCode, keyMessage = Validate.key(getPath(value), index)
    if keyCode then
        fail(keyCode, keyMessage :: string)
    end

    local child = (construct :: any)(nil, index, value, nil)
    if not children then
        children = {}
        rawset(value, Constants.CHILDREN_KEY, children)
    end
    children[index] = child

    return child
end

--__newindex: catches `data.coins = 5`, which would silently set a field on the wrapper instead of the data
const function onValueNewIndex(value: any, index: any, _: any)
    local here = pathOf(value)
    fail(
        "E_DIRECT_ASSIGN",
        `can't assign to {here}.{tostring(index)} directly, call it instead: {here}.{tostring(index)}(newValue)`
    )
end

const function onValueToString(value: any): string
    return `Value({pathOf(value)})`
end

--__call: no args reads, (value | updater, replicate?) writes
const function onValueCall(value: any, ...)
    local key = rawget(value, Constants.KEY_KEY)
    local raw = readRaw(value)

    local argCount = select("#", ...)
    if argCount == 0 then
        return raw
    end
    if argCount > 2 then
        fail("E_BAD_ARGUMENT", `{pathOf(value)}: expected (newValue, replicate?) but got {argCount} arguments`)
    end

    local param, replicateFlag = ...
    if replicateFlag ~= nil and typeof(replicateFlag) ~= "boolean" then
        fail(
            "E_BAD_ARGUMENT",
            `{pathOf(value)}: the second argument 'replicate' must be a boolean, got {typeof(replicateFlag)}`
        )
    end

    local newValue: any
    if typeof(param) == "function" then
        local results = table.pack((param :: any)(raw))
        if results.n == 0 then
            --without this a forgotten `return` would silently delete the value
            fail(
                "E_UPDATER_NO_RETURN",
                `{pathOf(value)}: the updater function returned nothing. Return the new value (return nil explicitly to remove it)`
            )
        end
        newValue = results[1]
    else
        newValue = param
    end

    local shouldReplicate = replicateFlag ~= false

    if key ~= nil then
        local parent = rawget(value, Constants.PARENT_KEY)
        local container = resolveContainer(value)
        if container == nil then
            fail(
                "E_PARENT_MISSING",
                `can't write {pathOf(value)}: {pathOf(parent)} is {typeof(readRaw(parent))}, not a table. Write the parent first`
            )
        end
        if table.isfrozen(container) then
            fail("E_FROZEN", `can't write {pathOf(value)}: {pathOf(parent)} is a frozen table`)
        end

        local oldValue = container[key]

        --same primitive = nothing to do. Same TABLE still counts as a write, it may have been
        --mutated in place (for example by an updater), so it must replicate and notify
        if oldValue == newValue and typeof(newValue) ~= "table" then
            return newValue
        end

        local path = getPath(value)

        local valueCode, valueMessage = Validate.value(path, newValue)
        if valueCode then
            fail(valueCode, valueMessage :: string)
        end

        local fitCode, fitMessage = Validate.fitsContainer(path, container, key, newValue)
        if fitCode then
            fail(fitCode, fitMessage :: string)
        end

        container[key] = newValue

        --replicate before callbacks run, see ArrayInsert
        if shouldReplicate then
            replicate(value, "Set", newValue)
        end

        if oldValue == nil and newValue ~= nil then
            Events.fireKey(parent, Constants.KEY_ADDED_KEY, key, newValue)
        elseif oldValue ~= nil and newValue == nil then
            Events.fireKey(parent, Constants.KEY_REMOVED_KEY, key, oldValue)
        end

        Events.fireChanged(value, oldValue)
        return newValue
    end

    --root
    if typeof(newValue) ~= "table" then
        fail("E_ROOT_NOT_TABLE", `the root Value must be set to a table, got {typeof(newValue)}`)
    end
    if table.isfrozen(raw) then
        fail("E_FROZEN", "can't write the root Value: its table is frozen")
    end

    local rootCode, rootMessage = Validate.value({}, newValue)
    if rootCode then
        fail(rootCode, rootMessage :: string)
    end

    local oldSnapshot = if newValue == raw then raw else table.clone(raw)
    if newValue ~= raw then --`data(data())` must not clear the table it is copying from
        for k in raw do
            raw[k] = nil
        end
        for k, v in newValue do
            raw[k] = v
        end
    end

    if shouldReplicate then
        replicate(value, "Set", newValue)
    end

    Events.fireChanged(value, oldSnapshot)
    return newValue
end
--#endregion

construct = function(raw, key, parent, replicateSink)
    local self = setmetatable({
        [Constants.KEY_KEY] = key,
        [Constants.PARENT_KEY] = parent,
        [Constants.CONTAINER_KEY] = raw, --only roots hold a table, children resolve through their parent
    }, {
        __index = onValueIndex,
        __newindex = onValueNewIndex,
        __call = onValueCall,
        __tostring = onValueToString,
    }) :: any

    --explicit sink wins (root), otherwise inherit from parent so every
    --descendant Value can reach it without walking the tree each write
    if replicateSink then
        rawset(self, Constants.REPLICATE_KEY, replicateSink)
    elseif parent then
        rawset(self, Constants.REPLICATE_KEY, rawget(parent, Constants.REPLICATE_KEY))
    end

    return self
end

--Value constructor, internal. Children are created automatically by indexing
--`raw` is the root table, `replicateSink` runs whenever the Value wants to replicate
function Value.new<T>(raw: T, key: string?, parent: Value<any>?, replicateSink: ReplicateSink?): Value<T>
    if key == nil and typeof(raw) ~= "table" then
        Log.error("E_BAD_ROOT", `Value.new expects a table, got {typeof(raw)}`, 2)
    end
    return (construct :: any)(raw, key, parent, replicateSink) :: any
end

return Value