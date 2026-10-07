return table.freeze({
    KEY_KEY = "___K", --key this Value occupies in its parent container
    PARENT_KEY = "___P", --parent Value, used to bubble changes upward
    CONTAINER_KEY = "___X", --the raw table this Value reads/writes through
    CHILDREN_KEY = "___C", --cache of child Values already created via indexing
    REPLICATE_KEY = "___S", --replication sink, inherited from parent
    CHANGED_KEY = "_ChangedCallbacks",
    ARRAY_INSERTED_KEY = "_OnInsertCallbacks",
    ARRAY_REMOVED_KEY = "_OnRemoveCallbacks",
    KEY_ADDED_KEY = "_OnKeyAddedCallbacks",
    KEY_REMOVED_KEY = "_OnKeyRemovedCallbacks",
})