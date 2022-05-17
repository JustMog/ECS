Mog ECS
===
This is an entity component system.
It aims to be as lightweight and simple to use as possible.

Overview
---

```lua
local ECS = require "ECS" -- or "path.to.ECS"

--- define a system  ---
local velocitySystem = { "pos", "vel" } -- required components
velocitySystem.name = "velocity" -- optional

function velocitySystem:init() --optional
    --setup here
end

-- define callbacks
function velocitySystem:update(dt)
    -- iterate entities with self.pool()
    for i, e in self.pool() do
        e.pos.x = e.pos.x + e.vel.x * dt
        e.pos.y = e.pos.y + e.vel.y * dt
    end
end

--- create a new world, passing systems ---
local world = ECS(velocitySystem)

--- add entities --
world:Entity({
    pos = { x = 100, y = 200 },
    vel = { x = 40, y = 30 },
})

function love.update(dt)
    -- emit events for all systems in a world
    world:emit("update", dt)
end

```

# Entities and Components

```lua
-- any table passed to a world's Entity() function becomes an entity in that world.
local e = {}
world:Entity(e) -- no need to set e to the returned value

-- simply setting a new key in the table to any value adds a component 
e.pos = { x = 0, y = 0 }
-- setting a key to nil removes that component
e.pos = nil

-- remove the entity from the world and all system pools
e.dead = true

```
System pools will be updated to reflect addition/removal of components before each new callback invocation.

# Systems

A simple table defines a system.
```lua
local velocitySystem = {}
```
### Pools:

```lua
-- to access entities, define pools using tables of required component names.
velocitySystem.entities = { "pos", "vel" }
-- use the same keys in system callbacks to access the pools.

-- you can also define a default pool with the key "pool" like so
local someSystem = { "someComponent", "someOtherComponent" }
```

```lua
-- in system callback, call the pool as a function to iterate over the entities in it
for i, e in self.entities() do
    -- do something with e
end

-- to sort or otherwise mutate the pool, you must create a copy:
local sortedEntities = self.entities:copy()
table.sort(sortedEntities)

for i, e in ipairs(sortedEntities) do
    -- do something with e
end
```

### Callbacks:

```lua
function system:init()
    -- called when the system is created, upon being passed to a world
end

function system:onAdded(entity, pool)
    -- called when an entity is added to one of the system's pools.
end

function system:onRemoved(entity, pool)
    -- called when an entity is removed from one of the system's pools.
end

```
Addition and removal of entities from pools happens before each new callback invocation.

Adding or removing components from entities within a callback won't be reflected in pools or trigger onAdded/onRemoved events immediately.

### Custom callbacks:
```lua
-- simply define a function
function system:onMousePressed(x, y, btn)
    -- do something
end

-- and pass its name and arguments to world:emit()
function love.mousepressed(x, y, btn)
    world:emit("onMousePressed", x, y, btn)
end
```
In callbacks, get the world a system is in with:
```lua
self:getWorld()
```

# Worlds
```lua
-- use the function returned by requiring ECS.lua to create a world:
local World = require "ECS"

-- pass systems definitions to the world:
local world = World(gravitySystem, velocitySystem)
```
Systems will receive callbacks in the order in which they were passed to create the world.
The system instances created from the passed definitions will be returned in a table along with the world:
```lua
local world, systems = World(gravitySystem, velocitySystem)

--[[ systems == {
    gravitySystem, 
    velocitySystem
}
```
If a system definition define a name, the returned table will also contain its instance under that key:
```lua
local namedSystem = { name = "mog" }
local world, systems = World(namedSystem)
--[[ systems == {
    namedSystem,
    mog = namedSystem
}
```
No validation for system names or component keys as yet so don't call them "())====D ~~~" or something.