// Interpretador do subconjunto de Python (port de interp.js): executa o script e monta a cena.
#pragma once
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

#include "ast.h"
#include "color.h"
#include "shape.h"
#include "value.h"

namespace tdi {

struct Scope {
  std::vector<std::pair<std::string, Value>> order;  // ordem de definição (para as dicas)
  std::unordered_map<std::string, size_t> index;
  std::shared_ptr<Scope> parent;
  explicit Scope(std::shared_ptr<Scope> parent = nullptr) : parent(std::move(parent)) {}
  Value *find(const std::string &name);  // procura subindo pelos pais
  bool hasOwn(const std::string &name) const { return index.count(name) > 0; }
  void set(const std::string &name, Value v);
  std::vector<std::string> names() const;
};
using ScopeP = std::shared_ptr<Scope>;

struct UserFunc : Func {
  std::vector<Param> params;
  bool hasStar = false;
  std::string star;
  Block body;
  NodeP lambdaBody;
  ScopeP closure;
  bool isLambda = false;
};

struct Interp {
  long maxSteps = 3000000, steps = 0;
  int depth = 0;
  std::vector<std::string> logs;
  Scene scene;
  Rng rng{1};
  ScopeP globals;
  std::vector<std::string> builtinNames;

  explicit Interp(long maxSteps = 3000000);
  Scene &run(const std::string &src);
  Value call(const Value &fn, const std::vector<Value> &args, const std::vector<std::pair<std::string, Value>> &kwargs, const Node *node);
  double random() { return rng(); }

 private:
  Builtins builtins();
  double toNum(const Value &x, const std::string &what);
  void tick(int line);
  void execBlock(const Block &b, const ScopeP &scope);
  void exec(const Node &s, const ScopeP &scope);
  void bindTarget(const Target &t, const Value &v, const ScopeP &scope, int line);
  void assign(const Node &t, const Value &v, const ScopeP &scope);
  std::vector<Value> evalItems(const Block &items, const ScopeP &scope);
  size_t normIndex(size_t len, const Value &idx, int line);
  Value eval(const Node &e, const ScopeP &scope);
  Value evalInner(const Node &e, const ScopeP &scope);
  Value getAttr(const Value &obj, const std::string &name);
};

struct RunResult {
  bool ok = false;
  std::shared_ptr<Interp> it;  // dono da cena
  ScriptError error{""};
  std::vector<std::string> logs;
};
RunResult runScript(const std::string &src, long maxSteps = 3000000);

Value binary(const std::string &op, const Value &a, const Value &b);

// módulos registrados à parte (rig, escopos, curvas, bibliotecas de geradores)
Builtins rigBuiltins(Interp &it);
Builtins scopeBuiltins(Interp &it);
Builtins curveBuiltins(Interp &it);
Builtins libBuiltins(Interp &it);
void registerExtraMethods();  // anchor/attach, planks/shingles/masonry...

}  // namespace tdi
