// Valores da linguagem (port de runtime.js): None, bool, número, texto, lista/tupla, dict, função,
// forma, expressão animada (time / x, y, z) e objetos (escopos, curvas, ossos...).
#pragma once
#include <array>
#include <functional>
#include <memory>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "error.h"
#include "json.h"

namespace tdi {

struct Node;
struct Value;
struct ListObj;
struct DictObj;
struct Func;
struct Shape;
struct Expr;
struct Object;
using ListP = std::shared_ptr<ListObj>;
using DictP = std::shared_ptr<DictObj>;
using FuncP = std::shared_ptr<Func>;
using ShapeP = std::shared_ptr<Shape>;
using ExprP = std::shared_ptr<Expr>;
using ObjP = std::shared_ptr<Object>;

struct Value {
  std::variant<std::monostate, bool, double, std::string, ListP, DictP, FuncP, ShapeP, ExprP, ObjP> v;

  Value() = default;
  Value(std::nullptr_t) {}
  Value(bool b) : v(b) {}
  Value(double d) : v(d) {}
  Value(int d) : v(double(d)) {}
  Value(long d) : v(double(d)) {}
  Value(long long d) : v(double(d)) {}
  Value(size_t d) : v(double(d)) {}
  Value(const char *s) : v(std::string(s)) {}
  Value(std::string s) : v(std::move(s)) {}
  Value(ListP p) : v(std::move(p)) {}
  Value(DictP p) : v(std::move(p)) {}
  Value(FuncP p) : v(std::move(p)) {}
  Value(ShapeP p) : v(std::move(p)) {}
  Value(ExprP p) : v(std::move(p)) {}
  Value(ObjP p) : v(std::move(p)) {}
  template <class T, class = std::enable_if_t<std::is_base_of_v<Object, T>>>
  Value(std::shared_ptr<T> p) : v(ObjP(std::move(p))) {}

  bool isNone() const { return v.index() == 0; }
  bool isBool() const { return v.index() == 1; }
  bool isNum() const { return v.index() == 2; }
  bool isStr() const { return v.index() == 3; }
  bool isList() const { return v.index() == 4; }
  bool isDict() const { return v.index() == 5; }
  bool isFunc() const { return v.index() == 6; }
  bool isShape() const { return v.index() == 7; }
  bool isExpr() const { return v.index() == 8; }
  bool isObj() const { return v.index() == 9; }

  bool b() const { return std::get<bool>(v); }
  double n() const { return std::get<double>(v); }
  const std::string &s() const { return std::get<std::string>(v); }
  const ListP &list() const { return std::get<ListP>(v); }
  const DictP &dict() const { return std::get<DictP>(v); }
  const FuncP &func() const { return std::get<FuncP>(v); }
  const ShapeP &shape() const { return std::get<ShapeP>(v); }
  const ExprP &expr() const { return std::get<ExprP>(v); }
  const ObjP &obj() const { return std::get<ObjP>(v); }
  template <class T> std::shared_ptr<T> as() const { return isObj() ? std::dynamic_pointer_cast<T>(obj()) : nullptr; }
  bool isTuple() const;
  size_t size() const;                     // lista/tupla
  const Value &operator[](size_t i) const; // lista/tupla
};

struct ListObj {
  std::vector<Value> items;
  bool tuple = false;
};

// dict com ordem de inserção; chaves comparadas como o Map do JS (números e textos por valor, o resto por identidade)
struct DictObj {
  std::vector<std::pair<Value, Value>> items;
  Value *find(const Value &k);
  void set(const Value &k, Value v);
};

// objetos com atributos próprios (escopos, curvas, ossos, esqueletos...)
struct Object : std::enable_shared_from_this<Object> {
  virtual ~Object() = default;
  virtual std::string typeName() const { return "objeto"; }
  virtual std::string describe() const { return "<" + typeName() + ">"; }
  virtual Value attr(const std::string &name);
  virtual Json plain() const;  // para os golden files (como plain() do golden.mjs)
};

ListP newList(std::vector<Value> items = {});
ListP newTuple(std::vector<Value> items = {});
Value list(std::vector<Value> items = {});
Value tuple(std::vector<Value> items = {});
Value tuple3(const std::array<double, 3> &v);

// ---------- funções ----------

struct Arg2 {
  std::string name;
  Value v;
};
// argumentos já ligados aos parâmetros (como o objeto que bindArgs devolve no JS)
struct Args {
  std::vector<Arg2> a;
  const Value &operator[](const std::string &k) const;
  bool has(const std::string &k) const;
  void set(const std::string &k, Value v);
};

struct Param2 {
  std::string name;
  bool required = false;
  Value def;
};

using NativeFn = std::function<Value(const Args &, const Node *)>;

struct Func {
  std::string name;
  virtual ~Func() = default;
  virtual bool isNative() const { return false; }
};

struct Native : Func {
  std::vector<Param2> params;
  std::string star;  // nome do *args (vazio: não tem)
  NativeFn fn;
  bool isNative() const override { return true; }
  std::string signature() const;
};

// "w", "h=None", "round=0", "*items", "axis=\"y\""
FuncP native(const std::string &name, std::initializer_list<const char *> params, NativeFn fn);
FuncP native(const std::string &name, const std::vector<std::string> &params, NativeFn fn);
Args bindArgs(const Native &f, const std::vector<Value> &args, const std::vector<std::pair<std::string, Value>> &kwargs);

// ---------- utilitários ----------

std::string typeName(const Value &v);
std::string repr(const Value &v);
std::string str(const Value &v);
std::string fmtNum(double x);
std::string jsNum(double x);  // String(x) do JS
int levenshtein(const std::string &a, const std::string &b);
std::string didYouMean(const std::string &word, const std::vector<std::string> &options);  // "" se nada perto
bool isInt(double x);

double num(const Value &v, const std::string &what);
Value numT(const Value &v, const std::string &what);
std::array<double, 2> vec2(const Value &v, const std::string &what);
std::array<double, 3> vec3(const Value &v, const std::string &what);
std::vector<Value> iterate(const Value &v);
bool truthy(const Value &v);
bool eq(const Value &a, const Value &b);
bool same(const Value &a, const Value &b);  // === do JS

// texto em UTF-8 tratado por pontos de código (len, índice, for c in s)
std::vector<std::string> codepoints(const std::string &s);

Json plain(const Value &v);
double round9(double x);

}  // namespace tdi
