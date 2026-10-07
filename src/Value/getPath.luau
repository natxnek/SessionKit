--!strict
--[[
    @author nat
    @date 07-10-26

    Converts a value into a path (array of strings)
]]
--Modules
const Constants = require("./Constants")
const ValueTypes = require("./ValueTypes")

return function(value: ValueTypes.Value<any>): { string }
    local path = {}
    local current = value
    while true do
        local key = rawget(current :: any, Constants.KEY_KEY)
        if key == nil then
            break
        end
        table.insert(path, 1, key)
        current = rawget(current :: any, Constants.PARENT_KEY)
    end
    return path
end
