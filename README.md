The `ecs.lua` file contains the entire ECS framework. The rest of this repository is a demo which both shows the framework in use, and provides a concrete sample of how to use it.

## API
### `ecs`
The ECS framework module.

`ecs.world(bitmask_size)` Creates a new world.
- `bitmask_size` [optional] - The number of 64-bit integers to use for bitmasks. Default is 4. You can register up to bitmask_size*64 components in a world, but higher numbers have a small performance cost.
- **Returns:** The world object.

`ecs.comp(world,tab,key,constructor)` Creates a new component type.
- `world` [optional] - The world object to register the component with.
- `tab` [optional] - The table to put the component in.
- `key` - The name of the component type.
- `constructor` - The function which creates a new instance of the component.
- **Returns:** A component type table which can be called to create new components.

`ecs.sys(world,include,exclude,func)` Creates a new set of system data.
- `world` [optional] - The world object to register the system with.
- `include` - The components which entities must have to be included in the query.
- `exclude` [optional] - The components which entities must not have to be included in the query
- `func` - The function which processes receives the query and processes the entities.
- **Returns:** The system data.

### `world`
A single independent instance of an ECS.

`world:comp(tab,key,constructor)` Alias for `ecs.comp(world,tab,key,constructor)` which automatically registers the component with the world.

`world:sys(include,exclude,func)` Alias for `ecs.sys(world,include,exclude,func)` which automatically registers the system with the world.

`world:reg_comp(comp_type)` Registers a component type with the world.
- `comp_type` - The component type to register.
- **Returns:** The world object, for chaining.

`world:reg_sys(sys_data)` Registers a system with the world.
- `system_data` - The system data to register.
- **Returns:** The world object, for chaining.

`world:ent()` Creates a new entity.
- **Returns:** The entity.

`world:run(sys_data,...)` Executes a system for the world.
- `sys_data` - The system data to execute.
- `...` - Additional arguments to pass to the system.
- **Returns:** The world object, for chaining.

### `query`
An iterator which returns a component for each entry in a system's `include` argument, plus the entity which possesses them.

### `entity`
`entity.comps` A map of all components on the entity. Keys are component type names, values are components. Can be used to fetch optional components or the components of referenced entities during system execution.

`entity:add(comp,key)` Adds a component to the entity. Calling a function created by `ecs.comp` will return both arguments at once.
- `comp` - The component to add.
- `key` - The name of the component type.
- **Returns:** The entity, for chaining.

`entity:remove(key)` Removes a component from the entity. Note that the act of removing it from the `entity.comps` table is deferred until the next system execution call.
- `key` - The name of the component type.
- **Returns:** The entity, for chaining.

`entity:ref()` Creates a weak reference to the entity. Useful for referencing entities from other entities.
- **Returns:** A callable table. When called, it will return the entity if it still exists, or nil if not.

`entity:destroy()` Queues the entity for destruction. Use this **during** system execution.

`entity:destroy_immediate()` Destroys the entity. Use this **outside** of system execution.
