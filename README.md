## API
### `ecs`
`ecs.ent()` Creates a new `entity`
- **Returns:** The entity.

`ecs.comp(tab,key,func)` Registers a new component type function.
- `tab` [optional] - The table to add the component generation function to. It will be under `key`.
- `key` - The name of the component type. Should be written as a field name.
- `func` - A function which initializes and returns a table containing the data for this component.
- **Returns:** A function which wraps `func`, returning both the result of `func` and `key`.

`ecs.sys(include,exclude,func)` Registers a new system.
- `include` An array of strings. Each string is the key of a component type. Each entity in the query will have **all** of these components.
- `exclude` [optional] - Same as include, but each entity in the query will have **none** of these components.
- `func` The function to execute upon calling the system. Accepts a `query` as the first argument.
- **Returns:** The function to call to execute the system.

### `query`
An iterator which returns a component for each entry in a system's `include` argument, plus the entity which possesses them.

### `entity`
`entity:add(comp,key)` Adds a component to the entity. Calling a function created by `ecs.comp` will return both arguments at once.
- `comp` The component to add.
- `key` The name of the component type to add.
- **Returns:** `entity`, for chaining.

`entity:remove(key)` Removes a component from the entity. Note that the act of removing it from the `entity.comps` table is deferred until the next system execution call.
- `key` The name of the component type to remove.
- **Returns:** `entity`, for chaining.

`entity:ref()` Creates a weak reference to the entity. Useful for referencing entities from other entities.
- **Returns:** A callable table. When called, it will return the entity if it still exists, or nil if not.

`entity:destroy()` Queues the entity for destruction after a system has finished executing. This should be used only **during** system executions.

`entity:destroy_immediate()` Destroys the entity. This should be used only **outside** of system executions.

`entity.comps` A map of all components on the entity. Keys are component type names, values are components. Can be used to fetch optional components or the components of referenced entities during system execution.
