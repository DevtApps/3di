// AST do subconjunto de Python do 3DI (mesmos nós e campos do parser.js; toJson() reproduz o JSON dele).
#pragma once
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "json.h"

namespace tdi {

struct Node;
using NodeP = std::shared_ptr<Node>;
using Block = std::vector<NodeP>;

enum class K {
  Pass, Break, Continue, Return, Assign, Aug, Expr, Def, If, For, While,
  Tuple, List, Starred, Lambda, IfExp, Or, And, Not, Cmp, Bin, Unary,
  Call, Attr, Index, Slice, Comp, Num, Str, Concat, Fmt, Name, Const, Dict,
};

// alvo de for/compreensão: um nome ou uma tupla de alvos
struct Target {
  std::string name;
  std::vector<Target> items;
  bool tuple = false;
};

struct Param {
  std::string name;
  NodeP def;  // pode ser nulo
};

struct Arg {
  NodeP e;
  std::string kw;  // vazio: posicional
  bool star = false;
  int line = 0;
};

struct Clause {
  Target target;
  NodeP iter;
  Block conds;
};

enum class ConstV { True, False, None };

struct Node {
  K k;
  int line = 0;
  double num = 0;           // Num
  std::string s;            // Str.v, Name.name, Attr.name, Def.name, op de Bin/Unary/Aug, Comp.kind
  ConstV cv = ConstV::None; // Const
  bool hasSpec = false;     // Fmt: spec != null
  std::string spec;
  NodeP e, a, b;            // e: Return/Expr/Starred/Not/Unary/Fmt; a/b: Bin/Or/And/IfExp
  NodeP cond;               // IfExp, While
  NodeP target, value;      // Aug (target), Assign/Aug (value)
  NodeP fn, obj, idx;       // Call.fn; Attr/Index.obj; Index.idx
  NodeP start, stop, step;  // Slice
  NodeP iter, elt, first, body1;  // For.iter; Comp.elt; Cmp.first; Lambda.body
  Block items;              // Tuple/List.items, Concat.parts, Cmp.rest, Assign.targets, Dict.keys
  Block values;             // Dict.values
  Block body;               // Def/For/While
  bool hasOrelse = false;   // If
  Block orelse;
  std::vector<std::pair<NodeP, Block>> tests;  // If
  std::vector<std::string> ops;                // Cmp
  std::vector<Param> params;                   // Def/Lambda
  bool hasStar = false;                        // Def: *args
  std::string star;
  std::vector<Arg> args;                       // Call
  std::vector<Clause> clauses;                 // Comp
  Target tgt;                                  // For

  Node(K k, int line) : k(k), line(line) {}
};

inline NodeP mk(K k, int line) { return std::make_shared<Node>(k, line); }

Json toJson(const Node &n);
Json toJson(const Block &b);

}  // namespace tdi
