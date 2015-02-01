local M = {}
M.CONTAINER_DATA_TYPES = {
    struct = true,
    list = true,
    map = true,
}

M.ATOM_DATA_TYPES = {
    int = {default = 1},
    bool = {default = false},
    string = {default = ''},
}

M.class_id_enum = 0
M.class_id_map = {}
M.class_name_map = {}
M.class_ref_map = {} -- class_id : [parent_id, ...]

function M.new_class_id()
    M.class_id_enum = M.class_id_enum + 1
    return M.class_id_enum
end

function M.get_class_byid(id)
    return M.class_id_map[id]
end

function M.get_class_byname(name)
    return M.class_name_map[name]
end

function M.get_class_name_byid(type_id)
    local class = M.get_class_byid(type_id)
    if not class then
        return nil
    end
    return class.name
end

function M.check_ref(node_id, parent_id)
    -- print('check ref', node_id, parent_id)
    if parent_id == nil then
        return
    end

    if parent_id == node_id then
        local name = M.get_class_name_byid(node_id)
        error(string.format('type<%s|%s> ref recursion define', name, node_id))
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


function M.load_class_define(class, parent_id)
    assert(class, "no class define")
    -- print('init obj type', class, class.name, class.type)

    local data_type = class.type
    local ref_class_name = string.match(data_type, "^$(.*)")
    if ref_class_name then
        local ref_type_id = M.get_class_byname(ref_class_name)
        if not ref_type_id then
            error(string.format("init class, ref illegal class<%s>", ref_class_name))
        end
        M.check_ref(ref_type_id, parent_id)
        class.id = ref_type_id
        return
    end

    if not data_type then
        error(string.format("init class<%s|%s> no data type", class.name, class.id))
    end

    local type_id = M.new_class_id()
    class.id = type_id
    M.check_ref(type_id, parent_id)
    M.class_id_map[type_id] = class
        
    -- name -> id map
    local class_name = class.name
    if class_name then
        if M.class_name_map[class_name] ~= nil then
            error(string.format("repeated obj define, name<%s>", class_name))
        end

        M.class_name_map[class_name] = type_id
    end

    if not M.CONTAINER_DATA_TYPES[data_type] then
        return
    end

    -- print('init obj type, parse struct data type', class.name, data_type)
    if data_type == 'struct' then
        assert(class.attrs, "not attrs")
        for k, v in pairs(class.attrs) do
            M.load_class_define(v, type_id)
        end
        return
    end

    if data_type == 'list' then
        M.load_class_define(class.item, type_id)
        return
    end

    if data_type == 'map' then
        M.load_class_define(class.key, type_id)
        M.load_class_define(class.value, type_id)
        return
    end

    error(string.format("unsupport data type<%s>", data_type))
end


function M.init(type_list)
    -- reset
    M.class_id_enum = 0
    M.class_id_map = {}
    M.class_name_map = {}
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
        return false, 'not data type'
    end

    if M.CONTAINER_DATA_TYPES[data_type] then -- no custom default
        return true, M.create_byid(class.id)
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


function M.parse_bool(s, class)
    if s == nil then
        return M.get_default(class)
    end

    return check_value(tostring(s) == 'true', class)
end


function M.parse_int(s, class)
    if s == nil then
        return M.get_default(class)
    end

    local value_a = tonumber(s)
    if value_a == nil then
        return false, string.format("<%s> not int", s)
    end

    local value_b = math.floor(value_a)
    if value_a ~= value_b then
        return false, string.format("<%s> not int", s)
    end
    return check_value(value_b, class)
end


function M.parse_float(s, class)
    if s == nil then
        return M.get_default(class)
    end

    local value = tonumber(s)
    if value == nil then
        return false, "not number"
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

    -- print('parse struct create obj', class.id, ret)
    return true, M.create_byid(class.id, ret)
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

    return true, M.create_byid(class.id, ret)
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
        if not string.match(k_data, "^__.*") then
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

    return true, M.create_byid(class.id, ret)
end


function M.get_parser(class)
    -- print('get parser by class', class, class.type, class.id)
    if class.id then
        local new_class = M.get_class_byid(class.id)
        if not new_class then
            return nil, class
        end
        class = new_class
    --     print('parse struct class', class.id, class.type)
    -- else
    --     print('parse atom class', class.type)
    end

    local func = M[string.format('parse_%s', class.type)]
    return func, class
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


function M.setfield(obj, k, v)
    -- print('setfield:', obj, obj.__class_id, k, v)
    local class_id = obj.__class_id
    if not class_id then
        error(string.format("no class id<%s>", k))
    end

    local class = M.get_class_byid(class_id)
    if not class then
        local class_name = M.get_class_name_byid(class_id)
        error(string.format("no class info<%s|%s>", class_name, class_id))
    end

    local data_type = class.type
    if data_type == 'struct' then
        -- check key exists
        local v_class = class.attrs[k]
        if not v_class then
            local class_name = M.get_class_name_byid(class_id)
            error(string.format('class<%s|%s> has no attr<%s>', class_name, class.id, k))
        end

        -- if v == nil, set node default
        local ok, v_data = M.load_node(v, v_class)
        if not ok then
            error(string.format("key<%s>, err:<%s>", k, v_data))
        end

        rawset(obj, k, v_data)
        return
    end

    if data_type == 'list' then
        if v ~= nil then -- if v == nil, remove node
            local v_class = class.item
            local ok, v_data = M.load_node(v, v_class)
            if not ok then
                error(string.format("key<%s>, err:<%s>", k, v_data))
            end
            v = v_data
        end
        rawset(obj, k, v)
        return
    end

    if data_type == 'map' then
        local ok, k_data = M.load_node(k, class.key)
        if not ok then
            error(string.format("key<%s>, err:<%s>", k, k_data))
        end

        if v ~= nil then -- if v == nil, remove node
            local ok, v_data = M.load_node(v, class.value)
            if not ok then
                error(string.format("key<%s>, err:<%s>", k, v_data))
            end
            v = v_data
        end
        rawset(obj, k_data, v)
        return
    end

    error(string.format("unsupport type<%s>", data_type))
end

M.mt = {}

function M.mt.__newindex(obj, k, v)
    -- print('__newindex', obj, k, v)
    return M.setfield(obj, k, v)
end

function M.mt.__oldindex(obj, k, v)
    -- print('__oldindex', obj, k, v)
    return M.setfield(obj, k, v)
end

function M.create_byid(class_id, data)
    local class = M.get_class_byid(class_id)
    if not class then
        error(string.format("create obj byid, illgeal class_id<%s>", class_id))
    end

    if data == nil then
        data = {}
    end

    local obj = {
        __class_id = class_id
    }
    setmetatable(obj, M.mt)

    -- check data type
    local data_type = class.type
    if data_type == 'struct' then
        for k, v in pairs(class.attrs) do
            -- print('init struct item', obj, k, data[k])
            obj[k] = data[k]
        end
        return obj
    end

    if data_type == 'list' then
        for idx, item in ipairs(data) do
            -- print('init list item', obj, idx, item)
            obj[idx] = item
        end
        return obj
    end

    if data_type == 'map' then
        for k, v in pairs(data) do
            -- print('init map item', obj, k, v)
            if not string.match(k, "^__.*") then
                obj[k] = v
            end
        end
        return obj
    end

    local name = M.get_class_name_byid(class_id)
    error(string.format("unsupport obj class<%s|%s>", name, class_id))
end


function M.create(class_name, data)
    local class_id = M.get_class_byname(class_name)
    if not class_id then
        error(string.format("create obj, illgeal class name<%s>", class_name))
    end
    return M.create_byid(class_id, data)
end


return M
