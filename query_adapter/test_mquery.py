# -*- coding:utf-8 -*-
import datetime
import time
import bson
import json
import mquery

t = int(time.time())
def test_matcher(rule_data, data):
    return mquery.match(mquery.BaseParser().parse(rule_data), data)

config = [
    {
        "func": mquery.encode_mongo,
        "cases": [
        ([["=", "key", 1]], {"key": 1}),
        ([[">", "key", 1]], {"key": {"$gt": 1}}),
        ([[">=", "key", 1]], {"key": {"$gte": 1}}),
        ([["<", "key", 1]], {"key": {"$lt": 1}}),
        ([["<=", "key", 1]], {"key": {"$lte": 1}}),
        ([["in", "key", [1, 2]]], {"key": {"$in": [1, 2]}}),
        
        # and, 0~2个有效子项
        ([["and", ["and"],
                 ["and", ["=", "key3", "c"], ["and"]],
                 ["and", ["=", "key1", "a"], ["=", "key2", "b"]],
         ]],
         {"key1": "a", "key2": "b", "key3": "c"},
        ),

        # and，合并相同key的子项
        # ([["and", ["=", "key", "a"], ["=", "key", "b"]]], None}), # conflict

        ([["and", 
           ["regex", "key_a", "a"], 
           ["regex", "key_a", "b"],
           ["=", "key_b", "c"]
         ]], # conflict, extend
         {
           "key_a": {"$regex": "a"},
           "$and": [{"key_a": {"$regex": "b"}}],
           "key_b": "c",
         }
        ),
        

        ([["and", [">", "key", "a"], ["<", "key", "b"]]], # extend
         {"key": {"$gt": "a", "$lt": "b"}}
        ),
        ([["and", ["in", "key", ["a", "b"]], [">", "key", "c"]]],  # atomic rule extend
         {"key": {"$in": ["a", "b"], "$gt": "c"}}
        ),

        ([["and", ["or", ["=", "key1", "a1"], ["=", "key1", "a2"]], # complex rule extend
                 ["or", ["=", "key2", "b1"], ["=", "key2", "b2"]],
                 ["not", ["=", "key3", "c"]],
                 ["not", ["=", "key4", "d"]],
                 ["and", ["in", "key5", ["e", "f"]]],
                 ["<", "key", 3],
                 [">", "key", 4],
         ]],
         {
                "$or": [
                    {"key1": "a1"},
                    {"key1": "a2"},
                    {"key2": "b1"},
                    {"key2": "b2"},
                ],
                "$not": {
                    "key3": "c",
                    "key4": "d"
                },
                "key5": {"$in": ["e", "f"]},
                "key":{"$lt": 3, "$gt": 4},
         }
        ),

        # or, 0~2个有效子项
        ([["or", ["or"],
                ["or", ["=", "key", 1], ["or"]], 
                ["or", ["=", "key2", 2], ["=", "key3", 3]], 
        ]], 
         {"$or": [{'key': 1}, 
                  {"$or": [{'key2': 2}, 
                           {'key3': 3}
                          ]
                  }
                 ]
         }
        ),
        # not, 0个有效子项
        ([["not", ["not"]]], {}),
        # not, 1个有效子项
        ([["not", ["in", "key1", ["a", "b"]]]],
         {"$not": {"key1": {"$in": ["a", "b"]}}},
        ),
        # not, 多个连续的单项not
        ([["not", ["not", ["not", ["not", ["not", ["=", "key", "a"]]]]]]],
         {"$not": {"key": "a"}},
        ),
        ([["not", ["and", ["not", ["=", "key", "a"]]]]],
         {"key": "a"},
        ),

        # 这里的not不应该消除
        ([["not", ["and", ["not", ["=", "key1", "a"]], ["=", "key2", "b"] ]]],
         {"$not":
              {"$not": {"key1": "a"},
               "key2": "b"
              }
         },
        ),
         
        # 自定义的范围操作, None为不用,其实是
        ([["range", "key", ["a", "b"]]], {"key": {"$gte": "a", "$lte": "b"}}),
        ([["range", "key", ["a", None]]], {"key": {"$gte": "a"}}),
        ([["range", "key", [None, "b"]]], {"key": {"$lte": "b"}}),
        ([["range", "key", [None, None]]], {}),

        ([["has", "key", ["a", "b", "c"]]], {"key": {"$regex": "a|b|c"}}),
        ([["regex", "key", "a|b|c"]], {"key": {"$regex": "a|b|c"}}),

        # 复合项
        ([["not", ["or", ["and", ["in", "key1", ["a", "b"]], ["=", "key2", "a"]]]]],
         {"$not": {"key1":{"$in": ["a", "b"]}, "key2":"a"}}
        ),
        
        # 特殊对象
        ([["in", "key", [None]]],
         {"key": {"$in": [None]}}
        ),

        ([["=", "key", {"$oid": "51622af03321b445eb2b2339"}]],
         {"key": bson.objectid.ObjectId("51622af03321b445eb2b2339")}
        ),

        ([["in", "key", [{"$date": t}]]],
         {"key": {"$in": [datetime.datetime.utcfromtimestamp(t)]}}
        ),

        # 替换
        ([["range", "key", ["a", "b"]],
          {"key": "key_b"}
         ],
         {"key_b": {"$gte": "a", "$lte": "b"}}
        ),

        # 错误检测
        ([["unsupported_op"]], None),
        ([["and", ["unsupported_op", "key1", "a",], ["=", "key2", "b"]]], None),
        ([["=", "key", {"$oid": "51622a"}]], None), # illegal objectid
        ([["=", "key", {"$date": "abc"}]], None), # illegal datetime

        # ([["and", 
        #     ["in", "player_name", ["player1", "player2", "player3"]], 
        #     ["or", ["range", "time", ["t1", "t2"]],  ["range", "time", ["t3", "t4"]]],
        #     ["or", ["regex", "chat",  "a|b|c"], ["regex", "chat",  "e|f|g"]]
        #   ]
        #  ],
        #  None
        # )
        ]},

        {
        "func": test_matcher,
        "cases": [
            ([["and", ["=", "key", 1]], {"key": 1}], True),
            ([["and", [">", "key", 1]], {"key": 1}], False),
            ([["and", [">=", "key", 1]], {"key": 1}], True),
            ([["and", ["<", "key", 1]], {"key": 1}], False),
            ([["and", ["<=", "key", 1]], {"key": 1}], True),
            ([["and", ["in", "key", [1, 2]]], {"key": 1}], True),
            ([["and", ["range", "key", [1, 2]]], {"key": 1.5}], True),
            ([["and", ["range", "key", [None, datetime.datetime(2013,3,28, 0, 0, 0)]]],
              {"key": datetime.datetime(2013,3,29, 0, 0, 0)}], 
             False),
            ([["and", ["regex", "key", "a|b|中文"]],
              {"key": "c中文d"}], 
             True),
            ([["and", ["has", "key", ["a", "b", "中文"]]],
              {"key": "c中文d"}], 
             True),
        ]
    }
]


def display(obj, indent=2):
    # s = str(obj).replace("ObjectId", "").replace("(","").replace(")", "")
    # return json.dumps(s, indent=indent, ensure_ascii=False)
    return obj


def test():
    for item in config:
        func = item["func"]
        cases = item["cases"]
        npass = 0
        nfail = 0
        for _args, _ex_out in cases:
            try:
                _out = func(*_args)
                passed = (_out == _ex_out)
            except mquery.ParseError, e:
                _out = e
                passed = (_ex_out is None) # if except out is None, means fail
        
            if passed:
                npass += 1
            else:
                nfail += 1
                print "FAIL:"
                print "\tinput:", _args
                print "\texcept output:", _ex_out
                print "\treal output:", _out
        print "test ", func, "pass:%s, fail:%s" % (npass, nfail)


if __name__ == "__main__":
    test()
    
