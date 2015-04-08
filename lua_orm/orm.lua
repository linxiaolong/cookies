local M = {}
M.KEYWORD_MAP = {
    boolean = true,
    number = true,
    string = true,
    struct = true,
    list = true,
    map = true,
}

M.CONTAINER_DATA_TYPES = {
    struct = true,
    list = true,
    map = true,
}

M.ATOM_DATA_TYPES = {
    number = {default = 0},
    boolean = {default = false},
    string = {default = ''},
}

M.KEY_ATTRS = {
    ['__class'] = true
}

M.class_map = {}
M.class_ref_map = {} -- class_name : [parent_name, ...]

function M.get_class(name)
    return M.class_map[name]
end

function M.check_ref(node_id, parent_id)
    -- print('check ref', node_id, parent_id)
    if parent_id == nil then
        return
    end

    if parent_id == node_id then
        error(string.format('type<%s> ref recursion define', node_id))
    end

    local p_map = M.class_ref_map[node_id]
    if not p_map then
        p_map = {}
        M.class_ref_map[node_id] = p_map
    end

    p_map[parent_id] = true -- record parent

    -- check and update parent's parent
    local pp_map = M.class_ref_map[parent_id]
    if not pp_map then
        pp_map = {}
        M.class_ref_map[parent_id] = pp_map
    end

    for pp_id, _ in pairs(pp_map) do
        M.check_ref(node_id, pp_id)
    end
end


function M.load_class_define(class, parent_name)
    assert(class, "no class define")
    -- print('init obj type', class.name, class.type)

    if parent_name ~= nil then
        class.name = parent_name .. "." .. class.name
    end
    local class_name = class.name

    if M.KEYWORD_MAP[class_name] then
        error(string.format("class name<%s> is keyword", class_name))
    end

    local data_type = class.type
    if not M.KEYWORD_MAP[data_type] then -- ref type
        local ref_class_name = data_type
        local ref_class = M.get_class(ref_class_name)
        if ref_class == nil then
            error(string.format("init class<%s|%s>, ref illegal ", class.name, data_type))
        end

        M.check_ref(ref_class.name, parent_name)
        data_type = ref_class.type
        class.name = ref_class.name
        local class_name = class.name
        return
    end

    if not data_type then
        error(string.format("init class<%s> no data type", class_name))
    end

    M.check_ref(class_name, parent_name)
    M.class_map[class_name] = class
    
    if not M.CONTAINER_DATA_TYPES[data_type] then
        return
    end

    -- print('init obj type, parse struct data type', class.name, data_type)
    if data_type == 'struct' then
        assert(class.attrs, "not attrs")
        for k, v in pairs(class.attrs) do
            v.name = k
            M.load_class_define(v, class_name)
        end
        return
    end

    if data_type == 'list' then
        class.item.name = 'item'
        M.load_class_define(class.item, class_name)
        return
    end

    if data_type == 'map' then
        class.key.name = 'key'
        M.load_class_define(class.key, class_name)
        class.value.name = 'value'
        M.load_class_define(class.value, class_name)
        return
    end

    error(string.format("unsupport data type<%s>", data_type))
end


function M.init(type_list)
    -- reset
    M.class_map = {}
    M.class_ref_map = {}

    for _, item in ipairs(type_list) do
        local name = item.name
        assert(name, 'not class name')
        M.load_class_define(item, nil)
    end
end


function M.get_traceback(err, keys, seq)
    local seq = seq and '.'
    if keys then
        path = table.concat(keys, seq)
        return string.format("key:<%s>, %s", path, err)
    else
        return err
    end
end


function check_value(value, rule)
    local value_type = rule.type
    if value_type == 'string' then
        if rule.set ~= nil and (rule.set[value] == nil) then
            return false, 'check set fail'
        end

        if rule.unset ~= nil and (rule.set[value] ~= nil) then
            return false, 'check unset fail'
        end

        return true, value
    end

    if value_type == 'int' or value_type == 'float' then
        if rule.min ~= nil and value < rule.min then
            return false, 'check min fail'
        end

        if rule.max ~= nil and value > rule.max then
            return false, 'check max fail'
        end

        if rule.set ~= nil and (rule.set[value] == nil) then
            return false, 'check set fail'
        end

        if rule.unset ~= nil and (rule.set[value] ~= nil) then
            return false, 'check unset fail'
        end
        return true, value
    end

    return true, value
end


function M.get_default(class)
    if class.required == true then
        return false, "is required"
    end

    local data_type = class.type
    if not data_type then
        return false, "no data type"
    end

    if M.CONTAINER_DATA_TYPES[data_type] then -- no custom default
        return true, M.create(class.name)
    end

    local atom_cfg = M.ATOM_DATA_TYPES[data_type]
    if atom_cfg then
        if class.default ~= nil then
            -- print('use custom_default', data_type, custom_default)
            return true, class.default
        end
    
        -- print('use type_default', data_type, atom_cfg.default)
        return true, atom_cfg.default
    end

    return false, string.format("unsupport type<%s>", data_type)
end


function M.parse_string(s, class)
    if s == nil then
        return M.get_default(class)
    end

    return check_value(tostring(s), class)
end


function M.parse_boolean(s, class)
    if s == nil then
        return M.get_default(class)
    end

    return check_value(tostring(s) == 'true', class)
end


function M.parse_number(s, class)
    if s == nil then
        return M.get_default(class)
    end

    local value = tonumber(s)
    if value == nil then
        return false, string.format("<%s> not number", s)
    end

    return check_value(value, class)
end


function M.parse_struct(data, class)
    if data == nil then
        return M.get_default(class)
    end

    -- print('parse struct')
    local ret = {}
    for attr_key, attr_class in pairs(class.attrs) do
        local attr_data = data[attr_key]
        local func, attr_class = M.get_parser(attr_class)
        if not func then
            return false, string.format("unsupport type<%s>", class.type)
        end

        -- print('parse struct attr', attr_key, attr_data, attr_class)
        local ok, attr_value, keys = func(attr_data, attr_class)
        if not ok then
            if keys == nil then keys = {} end
            table.insert(keys, 1, attr_key)
            return false, attr_value, keys
        end
        ret[attr_key] = attr_value
    end

    -- print('parse struct create obj', class.name, ret)
    return true, M.create(class.name, ret)
end


function M.parse_list(data, class)
    if data == nil then
        return M.get_default(class)
    end

    local ret = {}
    local func, item_class = M.get_parser(class.item)
    if not func then
        return false, string.format("unsupport type<%s>", item_class.type)
    end

    for item_idx, item_data in ipairs(data) do
        local ok, item_value, keys = func(item_data, item_class)
        if not ok then
            if keys == nil then keys = {} end
            table.insert(keys, 1, item_idx)
            return false, item_value, keys
        end
        table.insert(ret, item_value)
    end

    return true, M.create(class.name, ret)
end


function M.parse_map(data, class)
    if data == nil then
        return M.get_default(class)
    end

    local k_func, k_class = M.get_parser(class.key)
    if not k_func then
        return false, string.format("unsupport type<%s>", class.key.type)
    end

    local v_func, v_class = M.get_parser(class.value)
    if not v_func then
        return false, string.format("unsupport type<%s>", class.value.type)
    end

    local ret = {}
    for k_data, v_data in pairs(data) do
        if not M.KEY_ATTRS[k_data] then
            local ok, k_value, keys = k_func(k_data, k_class)
            if not ok then
                if keys == nil then keys = {} end
                table.insert(keys, 1, k_data)
                return false, k_data, keys
            end

            local ok, v_value, keys = v_func(v_data, v_class)
            if not ok then
                if keys == nil then keys = {} end
                table.insert(keys, 1, k_data)
                return false, v_data, keys
            end

            ret[k_value] = v_value
        end
    end
    return true, M.create(class.name, ret)
end


function M.get_parser(class)
    -- print('get parser by class', class, class.type, class.name)

    local func = M[string.format('parse_%s', class.type)]
    if func then
        return func, class
    end

    local ref_class = M.get_class(class.name)
    if not ref_class then
        return nil, ref_class
    end
    local func = M[string.format('parse_%s', ref_class.type)]
    return func, ref_class
end


function M.load_node(data, class)
    local func, class = M.get_parser(class)
    if not func then
        return false, string.format("unsupport type<%s>", class.type)
    end

    local ok, data, keys = func(data, class)
    if not ok then
        data = M.get_traceback(data, keys)
    end
    return ok, data
end


local function obj_next(obj, key)
    local next_key = next(obj, key)
    if not next_key then -- end
        return 
    end

    if M.KEY_ATTRS[next_key] then -- next key
        -- print('is key attr', next_key)
        return obj_next(obj, next_key) 
    end

    return next_key, obj[next_key] -- ok
end

M.struct_mt = {}
function M.struct_setfield(obj, k, v)
    local class_name = obj.__class
    if not class_name then
        error(string.format("no class<%s>", k))
    end

    local class = M.get_class(class_name)
    if not class then
        error(string.format("no class info<%s>", class_name))
    end

    local v_class = class.attrs[k]
    if not v_class then
        error(string.format('class<%s> has no attr<%s>', class_name, k))
    end

    -- optimize, trust class obj by name
    if type(v) == 'table' and v.__class ~= nil and M.class_map[v_class.name] then
        if v_class.name == v.__class then
            -- print(
            --     '-- struct trust class obj', 
            --     class.name, k, v_class.name, v.__class
            -- )
            rawset(obj, k, v)
            return
        end
        local s = string.format(
            'obj<%s.%s> value type not match, need<%s>, give<%s>',
            class_name, k, v_class.name, v.__class
        )
        error(s)
    end

    -- if v == nil, set node default
    local ok, v_data = M.load_node(v, v_class)
    if not ok then
        error(string.format("class<%s> key<%s>, err:<%s>", class_name, k, v_data))
    end

    rawset(obj, k, v_data)
end

function M.struct_mt.__newindex(obj, k, v)
    -- print('struct __newindex', obj, k, v)
    return M.struct_setfield(obj, k, v)
end

function M.struct_mt.__oldindex(obj, k, v)
    -- print('struct __oldindex', obj, k, v)
    return M.struct_setfield(obj, k, v)
end


M.list_mt = {}
function M.list_setfield(obj, k, v)
    local class_name = obj.__class
    if not class_name then
        error(string.format("no class<%s>", k))
    end

    local class = M.get_class(class_name)
    if not class then
        error(string.format("no class info<%s>", class_name))
    end

    if v == nil then -- if v == nil, remove node
        rawset(obj, k, nil)
        return
    end

    local v_class = class.item
    -- optimize, trust class obj by name
    if type(v) == 'table' and v.__class ~= nil and M.class_map[v_class.name] then
        if v_class.name == v.__class then
            -- print(
            --     '-- list trust class obj', 
            --     class.name, k, v_class.name, v.__class
            -- )
            rawset(obj, k, v)
            return
        end
        local s = string.format(
            'obj<%s.%s> value type not match, need<%s>, give<%s>',
            class_name, k, v_class.name, v.__class
        )
        error(s)
    end

    local ok, v_data = M.load_node(v, v_class)
    if not ok then
        error(string.format("class<%s> key<%s>, err:<%s>", class_name, k, v_data))
    end
    rawset(obj, k, v_data)
end

function M.list_mt.__newindex(obj, k, v)
    -- print('list __newindex', obj, k, v)
    return M.list_setfield(obj, k, v)
end

function M.list_mt.__oldindex(obj, k, v)
    -- print('list __oldindex', obj, k, v)
    return M.list_setfield(obj, k, v)
end


M.map_mt = {}
function M.map_setfield(obj, k, v)
    local class_name = obj.__class
    if not class_name then
        error(string.format("no class<%s>", k))
    end

    local class = M.get_class(class_name)
    if not class then
        error(string.format("no class info<%s>", class_name))
    end

    local ok, k_data = M.load_node(k, class.key)
    if not ok then
        error(string.format("class<%s> key<%s>, err:<%s>", class_name, k, k_data))
    end

    if v == nil then -- if v == nil, remove node
        rawset(obj, k_data, nil)
        return
    end

    local v_class = class.value
    -- optimize, trust class obj by name
    if type(v) == 'table' and v.__class ~= nil and M.class_map[v_class.name] then
        if v_class.name == v.__class then
            -- print(
            --     '-- map trust class obj', 
            --     class.name, k, v_class.name, v.__class
            -- )
            rawset(obj, k_data, v)
            return
        end

        local s = string.format(
            'obj<%s.%s> value type not match, need<%s>, give<%s>',
            class_name, k_data, v_class.name, v.__class
        )
        error(s)
    end

    local ok, v_data = M.load_node(v, class.value)
    if not ok then
        error(string.format("class<%s> key<%s>, err:<%s>", class_name, k, v_data))
    end
    rawset(obj, k_data, v_data)
end

function M.map_mt.__newindex(obj, k, v)
    -- print('map __newindex', obj, k, v)
    return M.map_setfield(obj, k, v)
end

function M.map_mt.__oldindex(obj, k, v)
    -- print('map __oldindex', obj, k, v)
    return M.map_setfield(obj, k, v)
end

function M.map_mt.__pairs(t)
    return obj_next, t, nil
end

M.mt_types = {
    struct = M.struct_mt,
    list = M.list_mt,
    map = M.map_mt,
}

function M.create(class_name, data)
    local class = M.get_class(class_name)
    if not class then
        error(string.format("create obj, illgeal class<%s>", class_name))
    end

    if data == nil then
        data = {}
    end

    local obj = {
        __class = class_name
    }

    -- check data type
    local data_type = class.type
    if data_type == 'struct' then
        setmetatable(obj, M.struct_mt)
        for k, v in pairs(class.attrs) do
            -- print('init struct item', obj, k, data[k])
            obj[k] = data[k]
        end
        return obj
    end

    if data_type == 'list' then
        setmetatable(obj, M.list_mt)
        for idx, item in ipairs(data) do
            -- print('init list item', obj, idx, item)
            obj[idx] = item
        end
        return obj
    end

    if data_type == 'map' then
        setmetatable(obj, M.map_mt)
        for k, v in pairs(data) do
            -- print('init map item', obj, k, v)
           if not M.KEY_ATTRS[k] then
                obj[k] = v
            end
        end
        return obj
    end

    error(string.format("unsupport obj class<%s>", class_name))
end

return M
