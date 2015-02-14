local orm = require 'orm'
tprint = require('extend').Table.print

-- test
local class_a = {
    ['name'] = 'class_a',
    ['type'] = 'struct',
    ['attrs'] = {
        ['a'] = {type = "int", default = 10},
        ['b'] = {type = "int"},
        ['c'] = {type = "bool"},
        ['d'] = {type = "string"},
    }
}


local class_b = {
    ['name'] = 'class_b',
    ['type'] = 'list',
    ['item'] = {type = "int"}
}


local class_c = {
    ['name'] = 'class_c',
    ['type'] = 'struct',
    ['attrs'] = {
        ['ref_a'] = {type = "$class_a"},
        ['ref_b'] = {type = "$class_b"},
    }
}

local class_d = {['name'] = 'class_d', type = "int", max=100}

local class_e = {
    ['name'] = 'class_e', 
    ['type'] = 'map',
    ['key'] = {type = "int", min=1},
    ['value'] = {type = "string"},
}

local class_f = {
    ['name'] = 'class_f', 
    ['type'] = 'struct',
    ['attrs'] = {
        ['a'] = {
            ['type'] = "struct",
            ['attrs'] = {
                ['b'] = {
                    ['type'] = "list",
                    ['item'] = {
                        ["type"] = "$class_d",
                    }
                }
            }
        },
        ['b'] = {
            ['type'] = "list",
            ['item'] = {
                ["type"] = "$class_e",
            }
        }
    }
}

print('[TC]: type init')
orm.init(
    {
        class_a,
        class_b,
        class_c,
        class_d,
        class_e,
        class_f,
    }
)
print('--- obj_class_id_map')
tprint(orm.class_id_map)
print('--- obj_class_name_map')
tprint(orm.class_name_map)

print('[TC]: struct init')
local obj_a = orm.create('class_a')
tprint(obj_a)

print('[TC]: struct set attr')
obj_a.a = nil
obj_a.b = 2
obj_a.c = true
obj_a.d = 'hello world'
tprint(obj_a)
for k, v in pairs(obj_a) do
    print(k, v)
end


print('[TC]: struct init by data')
local obj_a = orm.create('class_a', {a=10, b=100})
tprint(obj_a)

print('[TC]: list init by data')
local obj_b = orm.create('class_b', {4, 3, 2, 1})
tprint(obj_b)
print("len:", #obj_b)

print('[TC]: list insert and remove')
table.insert(obj_b, 11)
table.insert(obj_b, 12)
print("len:", #obj_b)
for idx, item in ipairs(obj_b) do
    print(idx, item)
end

print('[TC]: list remove')
print("len:", #obj_b)
table.remove(obj_b, 4)
for idx, item in ipairs(obj_b) do
    print(idx, item)
end

print('[TC]: list set')
obj_b[1] = 100
obj_b[2] = nil
tprint(obj_b)
print("len:", #obj_b)
for idx, item in ipairs(obj_b) do
    print(idx, item)
end

print('[TC]: type ref')
local obj_c = orm.create('class_c')
obj_c.ref_a = {a = 100}
obj_c.ref_a.a = 99
obj_c.ref_b = {1, 2, 3, 4, 5, 6}
tprint(obj_c)

print('[TC]: map')
local obj_e = orm.create('class_e', {[1] = '2', ['2'] = '2'})
tprint(obj_e)
for k, v in pairs(obj_e) do
    print(k, v)
end

print('[TC]: complex')
local obj_f = orm.create('class_f')
obj_f.a = {b = {3,4,5,6}}
obj_f.b = {{[1] = 2, [2] = 3},}
tprint(obj_f)


-- print('[TC]: type ref recursion define')
-- local class_f = {
--     ['name'] = 'class_f',
--     ['type'] = 'struct',
--     ['item'] = {
--         ['a'] = {type = "string", required = false, default="default_a"},
--         ['b'] = {
--             ['type'] = "list",
--             ['item'] = {
--                 ["type"] = "$class_f",
--             }
--         }
--     }
-- }

-- local class_g = {
--     ['name'] = 'class_g',
--     ['type'] = 'struct',
--     ['item'] = {
--         ['a'] = {type = "string", required = false, default="default_s"},
--         ['b'] = {type = "$class_h"},
--     }
-- }

-- local class_h = {
--     ['name'] = 'class_h',
--     ['type'] = 'struct',
--     ['item'] = {
--         ['a'] = {type = "string", required = false, default="default_s"},
--         ['b'] = {type = "$class_g"},
--     }
-- }
-- orm.init(
--     {
--         class_f,
--         -- class_g,
--         -- class_h,
--     }
-- )
