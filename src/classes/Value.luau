--!strict
--[[
    @author nat
    @date 15-09-26

    Value class
]]
local Value = {}

--#region Types
export type ValueOnChangeEvent<T> = (new: T, old: T?) -> ()
export type ValueOnKeyEvent<T> = (key: string, value: T) -> ()
export type ValueOnArrayEvent<T> = (value: T, index: number) -> ()

--Metas
--Methods available on every Value regardless of what it wraps
export type ValueGenericMeta<T> = {
    OnChange: (callback: ValueOnChangeEvent<T>, ignoreInitialData: boolean?) -> () -> (),
}
--Extra methods available when the wrapped value is a dictionary ({ [string]: T })
export type ValueDictionaryMeta<T> = {
    OnKeyAdded: (callback: ValueOnKeyEvent<T>) -> () -> (),
    OnKeyRemoved: (callback: ValueOnKeyEvent<T>) -> () -> (),
}
--Extra methods available when the wrapped value is an array ({ T })
export type ValueArrayMeta<T, U> = {
    Insert: (value: U, index: number?) -> number?,
    Remove: (index: number) -> U,

    OnInsert: (callback: ValueOnArrayEvent<U>) -> () -> (),
    OnRemove: (callback: ValueOnArrayEvent<U>) -> () -> (),
}

--Value type function (picks the value type based on the given generic type)
--Recursively builds the correct Value<T> shape depending on whether T is a
--primitive, an array, or a dictionary/struct, so children get typed Values too
export type function ValueType(T)
    local base = ValueBase(T)
    if not T:is("table") then
        return base
    end

    local indexer = T:indexer()
    if indexer then --{ [string]: T } or { any }
        local new = types.newtable()
        local index = indexer.index
        local result = indexer.readresult
        
        local valueBase = if index:is("number")
            then types.intersectionof(ValueArrayMeta(T, result), base)
            else types.intersectionof(ValueDictionaryMeta(result), base)

        new:setindexer(index :: any, ValueType(result :: any))
        return types.intersectionof(valueBase, new)
    else --{ a: x, b: y, c: z }
        local children = types.newtable()
        for key, prop in T:properties() do
            children:setproperty(key, ValueType(prop.read))
        end

        return types.intersectionof(base, children, ValueDictionaryMeta(types.any))
    end
end

--Base callable signature: call with no args to read, with a value
--(or updater function taking the current value) to write, optionally flagging replication
export type ValueBase<T> = ((value: (T | (current: T) -> T)?, replicate: boolean? ) -> T) & ValueGenericMeta<T>
export type Value<T> = ValueType<T>

--Replications
export type ReplicateOperation = "Set" | "Insert" | "Remove"
export type ReplicateSink = (path: { string }, operation: ReplicateOperation, a: any, b: any?) -> ()
--#endregion

--Constants
const KEY_KEY = "___K" --key this Value occupies in its parent container
const PARENT_KEY = "___P" --parent Value, used to bubble changes upward
const CONTAINER_KEY = "___X" --the raw table this Value reads/writes through
const CHILDREN_KEY = "___C" --cache of child Values already created via indexing
const REPLICATE_KEY = "___S" --replication sink, inherited from parent
const CHANGED_KEY = "_ChangedCallbacks"
const ARRAY_INSERTED_KEY = "_OnInsertCallbacks"
const ARRAY_REMOVED_KEY = "_OnRemoveCallbacks"
const KEY_ADDED_KEY = "_OnKeyAddedCallbacks"
const KEY_REMOVED_KEY = "_OnKeyRemovedCallbacks"

--Walks KEY_KEY/PARENT_KEY back to the root to build this Value's path
const function getPath(value: Value<any>): { string }
    local path = {}
    local current = value
    while true do
        local key = rawget(current :: any, KEY_KEY)
        if key == nil then
            break
        end
        table.insert(path, 1, key)
        current = rawget(current :: any, PARENT_KEY)
    end
    return path
end

--Bubbles a change up through every parent Value, not just the one that was set
const function fireChanged(value: Value<any>, oldValue: any)
    local function hasListeners(v: Value<any>): boolean
        if rawget(v, CHANGED_KEY) then return true end
        local children = rawget(v, CHILDREN_KEY)
        if children then
            for _, child in children do
                if hasListeners(child) then return true end
            end
        end
        return false
    end

    local function fireDeep(v: Value<any>, old: any)
        local new = (v :: any)()

        local callbacks = rawget(v, CHANGED_KEY)
        if callbacks then
            for _, callback in callbacks do
                task.spawn(callback, new, old)
            end
        end

        local children = rawget(v, CHILDREN_KEY)
        if children and typeof(old) == "table" and old ~= new then
            for key, child in children do
                if hasListeners(child) then
                    fireDeep(child, old[key])
                end
            end
        end
    end

    fireDeep(value, oldValue)

    local current = rawget(value, PARENT_KEY) :: any
    while current do
        local cbs = rawget(current, CHANGED_KEY)
        if cbs then
            local new = (current :: any)()
            for _, cb in cbs do task.spawn(cb, new, oldValue) end
        end
        current = rawget(current, PARENT_KEY)
    end
end

local function fireKeyEvent(container: Value<any>, listKey: string, key: string, valueAtKey: any)
    local callbacks = rawget(container :: any, listKey)
    if not callbacks then
        return
    end

    for _, callback in callbacks do
        task.spawn(callback, key, valueAtKey)
    end
end

--Registers a callback under this raw key, returns an unsubscribe function
const function createRegistrar(callbackListKey: string)
    return function(value: Value<any>)
        return function(callback: (...any) -> ())
            local callbacks = rawget(value :: any, callbackListKey)
            if not callbacks then
                callbacks = {}
                rawset(value :: any, callbackListKey, callbacks)
            end
            table.insert(callbacks, callback)

            --unsubscribe function closes over `callback` to find and remove it
            return function()
                local currentCallbacks = rawget(value :: any, callbackListKey)
                if not currentCallbacks then
                    return
                end
                local callbackIndex = table.find(currentCallbacks, callback)
                if callbackIndex then
                    table.remove(currentCallbacks, callbackIndex)
                end
            end
        end
    end
end

--each of these is a function(value) -> function(callback) -> unsubscribe,
--built once per event type via the shared registrar factory above
local function OnChange(value: Value<any>)
    return function(callback: ValueOnChangeEvent<any>, ignoreInitialData: boolean?)
        local callbacks = rawget(value :: any, CHANGED_KEY)
        if not callbacks then
            callbacks = {}
            rawset(value :: any, CHANGED_KEY, callbacks)
        end
        table.insert(callbacks, callback)

        if ignoreInitialData ~= true then
            local currentValue = (value :: any)()
            if currentValue ~= nil then
                task.spawn(callback, currentValue, nil)
            end
        end

        --unsubscribe function
        return function()
            local currentCallbacks = rawget(value :: any, CHANGED_KEY)
            if not currentCallbacks then
                return
            end
            local callbackIndex = table.find(currentCallbacks, callback)
            if callbackIndex then
                table.remove(currentCallbacks, callbackIndex)
            end
        end
    end
end
const OnInsert = createRegistrar(ARRAY_INSERTED_KEY)
const OnRemove = createRegistrar(ARRAY_REMOVED_KEY)
const OnKeyAdded = createRegistrar(KEY_ADDED_KEY)
const OnKeyRemoved = createRegistrar(KEY_REMOVED_KEY)

--Array insert registrar
local function ArrayInsert(value: Value<any>)
    return function(item: any, position: number?)
        local raw = value()
        local oldSnapshot = table.clone(raw)
        if position then
            table.insert(raw, position, item)
        else
            table.insert(raw, item)
        end

        fireChanged(value, oldSnapshot)

        local insertedAtPosition = position or #raw
        local insertedCallbacks = rawget(value :: any, ARRAY_INSERTED_KEY)
        if insertedCallbacks then
            for _, callback in insertedCallbacks do
                task.spawn(callback, item, insertedAtPosition)
            end
        end

        local sink: ReplicateSink = rawget(value :: any, REPLICATE_KEY)
        if typeof(sink) == 'function' then
            sink(getPath(value), "Insert", item, insertedAtPosition)
        end

        return insertedAtPosition
    end
end

--Array remove registrar
const function ArrayRemove(value: Value<any>)
    return function(position: number?)
        local raw = value()
        local oldSnapshot = table.clone(raw)
        local removedItem = table.remove(raw, position)

        fireChanged(value, oldSnapshot)

        local removedFromPosition = position or (#raw + 1)
        local removedCallbacks = rawget(value :: any, ARRAY_REMOVED_KEY)
        if removedCallbacks then
            --table.remove already shifted the array down, so the removed
            --index (when unspecified) was the old last slot, #raw + 1
            for _, callback in removedCallbacks do
                task.spawn(callback, removedItem, removedFromPosition)
            end
        end

        local sink: ReplicateSink = rawget(value :: any, REPLICATE_KEY)
        if typeof(sink) == 'function' then
            sink(getPath(value), "Remove", nil, removedFromPosition)
        end
        
        return removedItem
    end
end

--Maps method names accessible on a Value to the factory that builds them
const VALUE_FUNCTIONAL_KEYS = {
    OnChange = OnChange,
    Insert = ArrayInsert,
    Remove = ArrayRemove,
    OnInsert = OnInsert,
    OnRemove = OnRemove,
    OnKeyAdded = OnKeyAdded,
    OnKeyRemoved = OnKeyRemoved,
}

--__index metamethod: handles both method access and child Value creation/caching for plain keys
const function onValueIndex(value: Value<any>, index: string)
    const functionalKey = VALUE_FUNCTIONAL_KEYS[index]
    if functionalKey then
        return functionalKey(value)
    end

    local raw = value()
    assert(typeof(raw) == "table", `Attempted to index '{rawget(value :: any, KEY_KEY)}' ({typeof(raw)}) with '{index}'({typeof(index)})`)

    --reuse a previously created child Value for this key if one exists
    local children = rawget(value :: any, CHILDREN_KEY)
    if children and children[index] ~= nil then
        return children[index]
    end

    --otherwise lazily create and cache a new child Value pointing at `raw[index]`
    local newChild = Value.new<<any>>(raw, index, value)
    if not children then
        children = {}
        rawset(value :: any, CHILDREN_KEY, children)
    end
    children[index] = newChild

    return newChild
end

--__call metamethod: calling a Value with no args reads it, calling it with
--a value (or an updater function of the current value) writes it and fires
--the appropriate change/added/removed callbacks
const function onValueCall(value: Value<any>, ...)
    local rawParent = rawget(value :: any, CONTAINER_KEY)
    local key = rawget(value :: any, KEY_KEY)
    local raw = if key ~= nil then rawParent[key] else rawParent

    if select("#", ...) == 0 then
        --no arguments passed, treat this as a read
        return raw
    end

    local param, replicate = ...
    local newValue = if typeof(param) == "function" then (param :: any)(raw) else param

    if key ~= nil then
        local oldValue = rawParent[key]
        if oldValue == newValue then
            return newValue
        end

        local owner = rawget(value :: any, PARENT_KEY) or value
        rawParent[key] = newValue

        if oldValue == nil and newValue ~= nil then
            fireKeyEvent(owner, KEY_ADDED_KEY, key, newValue)
        elseif oldValue ~= nil and newValue == nil then
            fireKeyEvent(owner, KEY_REMOVED_KEY, key, oldValue)
        end

        fireChanged(value, oldValue)

        if replicate ~= false then
            local sink: ReplicateSink = rawget(value :: any, REPLICATE_KEY)
            if typeof(sink) == 'function' then
                sink(getPath(value), "Set", newValue)
            end
        end

        return newValue
    end

    assert(
        typeof(raw) == "table" and typeof(newValue) == "table",
        "Root Value must be set to a table"
    )

    local oldSnapshot = table.clone(raw)
    for k in raw do
        raw[k] = nil
    end
    for k, v in newValue do
        raw[k] = v
    end

    fireChanged(value, oldSnapshot)
    return newValue
end

--Value constructor, should used internally
--`raw` is the container this Value reads/writes through (parent table, or the root table itself when key is nil)
--`key` is nil for the root Value
--`replicateSink` is the function that runs whenever value wants to replicate to the client
function Value.new<T>(raw: T, key: string?, parent: Value<any>?, replicateSink: ReplicateSink?): Value<T>
    local self = setmetatable({
        [KEY_KEY] = key,
        [PARENT_KEY] = parent,
        [CONTAINER_KEY] = raw,
    }, {
        __index = onValueIndex,
        __call = onValueCall,
    }) :: any

    --explicit sink wins (root), otherwise inherit from parent so every
    --descendant Value can reach it without walking the tree each write
    if replicateSink then
        rawset(self, REPLICATE_KEY, replicateSink)
    elseif parent then
        rawset(self, REPLICATE_KEY, rawget(parent :: any, REPLICATE_KEY))
    end

    return self
end

return Value
