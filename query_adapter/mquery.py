# -*- coding:utf-8 -*-
"""
   rule(规则): 
       简单: op + 字段 + 条件参数
       组合: op + rules
       ex: ["in" "col" "a", "b"]
           [rule_op rule1 rule2]

   rule_op(规则操作符):
       所有参数是rule
       限定范围: and, or, not

   key_op(字段操作符):
       第一个参数是目标字段，之后是条件参数
       限定范围: =, >, >=, <, <=, in
       
   sugar语法糖操作符:
       解析时替换rule
       限定范围: range
"""

import re
import bson
import copy
import datetime

class ParseError(Exception):
    pass

def load_bson_id(d):
    try:
        return bson.objectid.ObjectId(d.get('$oid'))
    except:
        raise ParseError("illegal objectid: %s" % d)

def load_bson_date(d):
    try:
        return datetime.datetime.utcfromtimestamp(d.get('$date'))
    except:
        raise ParseError("illegal datetime: %s" % d)


def is_bson_id(d):
    return isinstance(d, dict) and d.has_key('$oid')


def is_bson_date(d):
    return isinstance(d, dict) and d.has_key('$date')


def load_bson(value):        
    if is_bson_id(value):
        return load_bson_id(value)

    if is_bson_date(value):
        return load_bson_date(value)

    if isinstance(value, list):
        return [load_bson(item) for item in value]

    if isinstance(value, dict):
        ret = {}
        for k, v in value.iteritems():
            ret[k] = load_bson(v)
        return ret
    return copy.deepcopy(value)


def check_complex_rule_args(func):
    def _func(self, rule):
        args = rule.args
        if not(isinstance(args, list) and any(args)):
            return self.rule_class()
        return func(self, rule)
    return _func


def check_atomic_rule_args(func):
    def _func(self, rule):
        args = rule.args
        if not(isinstance(args, list) and len(args) > 1):
            raise ParseError("illegal rule args: %s" % args)
        key, value = args
        if not key.__hash__:
            raise ParseError("unhashable rule key: %s" % key)
        return func(self, rule)
    return _func


complex_ruleops = set(["or", "not", "and"])
atomic_ruleops = set(["=", "<", "<=",">", ">=", "in", "range", "regex", "has"])
def get_optype(op):
    if op in complex_ruleops:
        return 'complex'
    if op in atomic_ruleops:
        return 'atomic'
    return None


class BaseRule:
    """基本的规则数据"""
    def __init__(self):
        self.data = None
        self._op = None
        self.args = None
        self.children = []

    def set_data(self, data):
        self.data = data
        if not(isinstance(data, list) and any(data)):
            raise ParseError("illegal rule data: %s" % data)
        self.set_op(data[0])
        self.args = data[1:]

    def set_op(self, op):
        self._op = op
        self._op_type = get_optype(op)
        if not self._op_type:
            raise ParseError("unsupported rule op: %s" % op)
    
    def get_op(self):
        return self._op

    def isatomic(self):
        return self._op_type == 'atomic'

    def isempty(self):
        """用于表达无用规则, 比如["and"]"""
        return self._op is None


class BaseParser:
    """抽取出的解析流程"""
    def __init__(self, rule_class=BaseRule):
        self.parsers = {
            "=": self.parse_atomic_rule,
            "<": self.parse_atomic_rule,
            "<=": self.parse_atomic_rule,
            ">": self.parse_atomic_rule,
            ">=": self.parse_atomic_rule,
            "in": self.parse_in,

            "and": self.parse_and,
            "or": self.parse_or,
            "not": self.parse_not,

            "range": self.parse_range, # range, key, [begin, end]
            "has": self.parse_has, # has, key, [a, b, c] => 转成正则
            "regex": self.parse_atomic_rule,
        }
        self.rule_class = rule_class

    def parse(self, data, key_trans={}):
        self.key_trans = key_trans
        rule = self.rule_class()
        rule.set_data(data) # set data，会解析出op和args，但不会解析出children和value
        parser = self.parsers.get(rule.get_op())
        if not parser:
            raise ParseError("unsupported op:%s of rule data:%s" % (rule.get_op(), rule.data))
        return parser(rule) # 解析出children和value

    def get_final_key(self, key):
        return self.key_trans.get(key, key)

    @check_atomic_rule_args
    def parse_atomic_rule(self, rule): # =, <, >, <=, >=
        key = self.get_final_key(rule.args[0])
        rule.value = (key, rule.args[1])
        return rule

    @check_atomic_rule_args
    def parse_in(self, rule):
        key = self.get_final_key(rule.args[0])
        values = rule.args[1]
        if not(isinstance(values, list)):
            raise ParseError("illegal in rule values: %s" % values)

        if len(values) == 0: # 没有子项时去除
            return self.rule_class()
        rule.value = (key, values)
        return rule

    @check_complex_rule_args
    def parse_and(self, rule):
        children = [self.parse(arg, self.key_trans) for arg in rule.args]
        children = [child for child in children if not child.isempty()]
        n = len(children)
        if n == 0:  # 如果没有子项，返回空
            return self.rule_class()
        elif n == 1: # 如果没有只有一个子项，去掉or
            return children[0]
        rule.children = children # 设置子节点
        return rule

    @check_complex_rule_args
    def parse_or(self, rule):
        children = [self.parse(arg, self.key_trans) for arg in rule.args]
        children = [child for child in children if not child.isempty()]
        n = len(children)
        if n == 0:  # 如果没有子项，返回空
            return self.rule_class()
        elif n == 1: # 如果没有只有一个子项，去掉or
            return children[0]
        rule.children = children # 设置子节点
        return rule

    @check_complex_rule_args
    def parse_not(self, rule):
        target_rule = self.parse(rule.args[0], self.key_trans) # 只关注第一项
        if target_rule.isempty():
            return target_rule

        if target_rule.get_op() == "not":
            return target_rule.children[0]
        rule.children = [target_rule]
        return rule

    @check_atomic_rule_args
    def parse_range(self, rule):
        """
        自定义range，range(a, b) => (and, (< x a), (> x b))
        其实是一种语法糖
        """
        key, value = rule.args
        if not(isinstance(value, list) and len(value) == 2):
            raise ParseError("illegal range rule value: %s" % value)
        begin, end = value
        ret = self.rule_class()
        ret.set_op("and")
        if begin is not None:
            ret.children.append(self.parse([">=", key, begin], self.key_trans))
        if end is not None:
            ret.children.append(self.parse(["<=", key, end], self.key_trans))
        return ret

    @check_atomic_rule_args
    def parse_has(self, rule):
        """
        自定义的has, has key [a, b, c] => regex key a|b|c
        """
        key, values = rule.args
        if not(isinstance(values, list)):
            raise ParseError("illegal in rule values: %s" % values)

        if len(values) == 0: # 没有子项时去除
            return self.rule_class()

        try: # 字符串统一使用unicode，将数字等转为字符串
            items = []
            for value in values:
                value_type = type(value)
                if value_type != unicode:
                    value = str(value)
                value = value.strip()
                if value:
                    items.append(value)
            s = "|".join(items)
        except:
            raise ParseError("illegal has rule values: %s" % s)

        ret = self.rule_class()
        ret.set_op("regex") # 转成正则
        ret.value = (key, s)
        return ret


MONGO_OPS = {
    "or": "$or",
    "not": "$not",
    ">": "$gt",
    ">=": "$gte",
    "<": "$lt",
    "<=": "$lte",
    "in": "$in",
    "regex": "$regex",
}
class MongoRule(BaseRule):
    @staticmethod
    def _extend_atomic_rule_value(ret, rule):
        for key, value in rule.get_value().iteritems():
            if key not in ret: # 没有相同key的
                ret[key] = value
                continue

            conflict_ops = set(ret[key].keys()) & set(value.keys())
            if any( conflict_ops ): # 存在冲突，另开$and合并
                if "$and" not in ret:
                    ret["$and"] = []
                ret["$and"].append({key: value})
            else:
                ret[key].update(value)

    @staticmethod
    def _extend_complex_rule_value(ret, childrens):
        for op, rules in childrens.iteritems():
            # 将多项and(a, b, c), and(e, f) 合为and(a, b, c, e, f)
            # 将多项or(a, b, c), or(e, f) 合为or(a, b, c, e, f)
            if op in set(["and", "or"]): 
                new_rule = MongoRule()
                new_rule.set_op(op)
                new_rule.children = []
                for rule in rules:
                    new_rule.children.extend(rule.children)
                ret.update(new_rule.get_value())
                continue

            if op == "not": # 将多项not(a), not(b) 合为 not(and(a, b))
                new_rule = MongoRule()
                new_rule.set_op("and")
                new_rule.children = [rule.children[0] for rule in rules]

                new_rule2 = MongoRule()
                new_rule2.set_op(op)
                new_rule2.children = [new_rule]
                ret.update(new_rule2.get_value())
                continue
            raise ParseError("unsupported rule op: %s" % op)
        return

    @staticmethod
    def _value_getter_and(rule):
        ret = {}
        complex_children = {}
        for child in rule.children:
            if child.isempty():
                continue

            child_op = child.get_op()
            if child.isatomic():
                MongoRule._extend_atomic_rule_value(ret, child)
                continue

            if complex_children.has_key(child_op):
                complex_children[child_op].append(child)
            else:
                complex_children[child_op] = [child]

        MongoRule._extend_complex_rule_value(ret, complex_children) # 合并复杂子项
        return ret

    @staticmethod
    def _value_getter_or(rule):
        return {MONGO_OPS[rule.get_op()]: [item.get_value() for item in rule.children]}

    @staticmethod
    def _value_getter_not(rule):
        return {MONGO_OPS[rule.get_op()]: rule.children[0].get_value()}

    @staticmethod
    def _value_getter_eq(rule):
        key, val = rule.value
        return {key: load_bson(val)}

    @staticmethod
    def _value_getter_atomic(rule):
        key, val = rule.value
        return {key: {MONGO_OPS[rule.get_op()]: load_bson(val)}}

    def __init__(self):
        BaseRule.__init__(self)
        self.value_getters = {
            "and": MongoRule._value_getter_and,
            "or": MongoRule._value_getter_or,
            "not": MongoRule._value_getter_not,
            "=": MongoRule._value_getter_eq,
            ">": MongoRule._value_getter_atomic,
            ">=": MongoRule._value_getter_atomic,
            "<": MongoRule._value_getter_atomic,
            "<=": MongoRule._value_getter_atomic,
            "in": MongoRule._value_getter_atomic,
            "regex": MongoRule._value_getter_atomic
        }
    
    def get_value(self):
        # 判断类型，如果有子节点返回组合结果
        if self.isempty():
            return {}

        value_getter = self.value_getters.get(self.get_op())
        if not value_getter:
            raise ParseError("unsupported rule op: %s" % op)
        
        return value_getter(self)


def encode_mongo(rule, key_trans={}):
    """
    mquery的查询规则 -> mongo的查询规则
    反过来容易很多，需要时再添加
    """
    return BaseParser(MongoRule).parse(rule, key_trans).get_value()


def find_value(path, data):
    """
    data是一个dict, key用.分割
    """
    context = data
    for key in path.split('.'):
        key = key.strip()
        if key != "":
            context = context[key]
    return context
    

def check_atomic_rule_matcher_args(func):
    def _func(rule_obj, data):
        key, val_b = rule_obj.value
        try: # 找不到的情况
            val_a = find_value(key, data)
        except LookupError, e:
            print "LookupError:", key, data
            return False
        try:
            return func(val_a, val_b)
        except:
            raise ParseError("op error: %s %s %s" % (val_a, rule_obj.get_op(), val_b))
    return _func


def rule_matcher_and(rule_obj, data):
    if not any(rule_obj.children):
        return True
    for child in rule_obj.children:
        if not match(child, data):
            return False
    return True

def rule_matcher_or(rule_obj, data):
    if not any(rule_obj.children):
        return True

    for child in rule_obj.children:
        if match(child, data):
            return True
    return False

def rule_matcher_not(rule_obj, data):
    return not match(rule_obj.children[0], data)

@check_atomic_rule_matcher_args
def rule_matcher_in(a, b):
    return a in b

@check_atomic_rule_matcher_args
def rule_matcher_eq(a, b):
    return a == b

@check_atomic_rule_matcher_args
def rule_matcher_lt(a, b):
    return a < b

@check_atomic_rule_matcher_args
def rule_matcher_lte(a, b):
    return a <= b

@check_atomic_rule_matcher_args
def rule_matcher_gt(a, b):
    return a > b

@check_atomic_rule_matcher_args
def rule_matcher_gte(a, b):
    return a >= b

@check_atomic_rule_matcher_args
def rule_matcher_regex(a, b):
    # print "regex:", b, a, re.search(b, a)
    return re.search(b, a) is not None


RULE_MATCHERS = {
    "and": rule_matcher_and,
    "or": rule_matcher_or,
    "not": rule_matcher_not,
    "=": rule_matcher_eq,
    "<": rule_matcher_lt,
    "<=": rule_matcher_lte,
    ">": rule_matcher_gt,
    ">=": rule_matcher_gte,
    "in": rule_matcher_in,
    "regex": rule_matcher_regex
}
def match(rule_obj, data):
    """
    检测data是否符合rule的要求
    """
    if rule_obj.isempty():
        return True
    rule_op = rule_obj.get_op()
    rule_matcher = RULE_MATCHERS.get(rule_op)
    if not rule_matcher:
        raise ParseError("unsupported rule matcher op: %s" % rule_op)
    return rule_matcher(rule_obj, data)

