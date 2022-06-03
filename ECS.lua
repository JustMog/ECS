
local Entity = {}

function Entity:__index(k)
   local c = self._components[k]
   return c ~= nil and c or Entity[k]
end

local worldRecheckEntity
function Entity:__newindex(k, v)
    local hadComponent = self._components[k] ~= nil
    local gotComponent = v ~= nil

    self._components[k] = v

    if hadComponent ~= gotComponent then
        worldRecheckEntity(self._world, self)
    end
end

---------------------------------------------

local Pool = {}
Pool.__index = Pool

local makeAccessor
function Pool:new(filter)

    local pool = setmetatable({
        keys = filter,
        entities = {},
        listeners = {},
        iterators = {},
    }, Pool)

    pool.accessor = makeAccessor(pool)
    return pool
end

function makeAccessor(pool)
    local accessor, mt = {}, {}

    function mt:__call()
        table.insert(pool.iterators, 0)

        return function()
            local i = pool.iterators[#pool.iterators]
            i = i + 1

            if i > #pool.entities then
                table.remove(pool.iterators)
                return
            end

            pool.iterators[#pool.iterators] = i
            return pool.entities[i]
        end
    end
    return setmetatable(accessor, mt)
end

function Pool:filter(e)
    for _, key in ipairs(self.keys) do
        if not e[key] then return false end
    end
    return true
end

function Pool:recheck(e)
    local match = (not e.dead) and self:filter(e)

    local hasEntity = self.entities[e]

    if match and not hasEntity then
        table.insert(self.entities, 1, e)
        self.entities[e] = true

        for iterNum, iterVal in ipairs(self.iterators) do
            self.iterators[iterNum] = iterVal + 1
        end

        self:onAdded(e)

    elseif hasEntity and not match then

        for entityNum, entity in ipairs(self.entities) do
            if entity == e then
                table.remove(self.entities, entityNum)
                self.entities[e] = nil

                for iterNum, iterVal in ipairs(self.iterators) do
                    if entityNum <= iterVal then
                        self.iterators[iterNum] = iterVal - 1
                    end
                end
                self:onRemoved(e)
                break

            end
        end

    end
end

function Pool:onAdded(e)
    for _, listener in ipairs(self.listeners)  do
        if listener.onAdded then listener:onAdded(e, self.accessor) end
    end
end

function Pool:onRemoved(e)
    for _, listener in ipairs(self.listeners)  do
        if listener.onRemoved then listener:onRemoved(e, self.accessor) end
    end
end

---------------------------------------------

local World = {}
World.__index = World

local newSystem

local function newWorld(...)
    local world = setmetatable({
        _systems = {},
        _pools = {},
    }, World)

    local systems = {}
    for _, system in ipairs{...} do
        system = newSystem(system, world)
        table.insert(world._systems, system)

        table.insert(systems, system)
        if system.name then systems[system.name] = system end
    end

    return world, systems
end

--adding  entities simply wraps them with a metatable
--such that the world is updated when keys are added or removed
function World:Entity(e)
    e = e or {}
    if e._world then error("Entity already added to a world", 2) end
    --ensure removed and readded entities aren't immediately removed again
    e.dead = nil

    local components = {}
    for k, v in pairs(e) do
        components[k] = v
        e[k] = nil
    end
    e._components = components
    e._world = self
    setmetatable(e, Entity)

    worldRecheckEntity(self, e)
    return e
end

--on removal simply remove the wrapper, leaving the entity otherwise untouched
local function removeEntity(e)
    e._world = nil
    setmetatable(e, nil)
    for k, v in pairs(e._components) do e[k] = v end
    e._components = nil
end

function worldRecheckEntity(world, e)
    for _, pool in ipairs(world._pools) do
        pool:recheck(e)
    end
    if e.dead then removeEntity(e) end
end

function World:emit(event, ...)
    for _, system in ipairs(self._systems) do
        if type(system[event]) == "function" then
            system[event](system, ...)
        end
    end
end

---------------------------------------------

local getPool
function newSystem(def, world)
    local d = {}
    for k, v in pairs(def) do d[k] = v end
    def = d

    local s = { name = def.name, getWorld = function() return world end }

    if #def > 0 then def.pool = def.pool or def end

    for poolName, v in pairs(def) do
        if type(v) == "table" then
            local pool = getPool(v, world, poolName, def.name)
            s[poolName] = pool.accessor
            table.insert(pool.listeners, s)
        end
    end

    def.__index = def
    setmetatable(s, def)

    if s.init then s:init() end
    return s
end

local poolErr
function getPool(filter, world, poolName, systemName)

    if #filter <= 0 then poolErr(poolErr, systemName) end
    for _, v in ipairs(filter) do
        if type(v) ~= "string" then poolErr(poolName, systemName) end
    end

    table.sort(filter)
    local hash = table.concat(filter, ",")
    local existingPool = world._pools[hash]
    if existingPool then return existingPool end

    local pool = Pool:new(filter)
    world._pools[hash] = pool
    table.insert(world._pools, pool)
    return pool
end

function poolErr(poolName, systemName)
    error(
        ("Invalid pool definition for %s, pool '%s'. must be a table of keys")
        :format(systemName and ("system '%s'"):format(systemName) or "unnamed system", poolName)
    , 5)
end

return newWorld