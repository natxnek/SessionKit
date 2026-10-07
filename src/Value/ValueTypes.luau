--!strict
--[[
    @author nat
    @date 07-10-26

    Value types
]]
--Event types
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

return nil