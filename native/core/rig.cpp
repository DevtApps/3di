#include "rig.h"

#include <algorithm>
#include <cmath>
#include <map>
#include <set>

#include "expr.h"

namespace tdi {

V3 Bone::tail() const {
  if (hasTail) return tailSpec;
  if (!children.empty()) return children[0]->head;
  if (parent) {
    V3 d{head[0] - parent->head[0], head[1] - parent->head[1], head[2] - parent->head[2]};
    double len = std::sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
    if (len == 0) len = 1;
    double k = std::max(0.05, len / 3);
    return {head[0] + d[0] / len * k, head[1] + d[1] / len * k, head[2] + d[2] / len * k};
  }
  return {head[0], head[1] + 0.1, head[2]};
}

bool Bone::animated() const {
  for (auto &a : angles) if (a.isExpr()) return true;
  for (auto &a : offset) if (a.isExpr()) return true;
  return false;
}

std::string Bone::describe() const { return "<osso " + name + " em (" + fmtNum(head[0]) + ", " + fmtNum(head[1]) + ", " + fmtNum(head[2]) + ")>"; }

Json Bone::plain() const {
  Json o = Json::object();
  o.set("$", "Bone");
  o.set("name", name);
  return o;
}

Value Bone::attr(const std::string &n) {
  auto self = std::static_pointer_cast<Bone>(shared_from_this());
  if (n == "__bone__") return true;
  if (n == "name") return name;
  if (n == "head") return tuple3(head);
  if (n == "tail") return tuple3(tail());
  if (n == "parent") return parent ? Value(parent) : Value();
  if (n == "length") { V3 t = tail(); return std::hypot(t[0] - head[0], t[1] - head[1], t[2] - head[2]); }
  if (n == "rotate" || n == "move") {
    bool rot = n == "rotate";
    return native(n, {"x=0", "y=0", "z=0"}, [self, rot, n](const Args &a, const Node *) -> Value {
      std::vector<Value> v;
      if (a["x"].isList()) { V3 q = vec3(a["x"], n); v = {q[0], q[1], q[2]}; }
      else v = {a["x"], a["y"], a["z"]};
      auto &dst = rot ? self->angles : self->offset;
      for (int i = 0; i < 3; i++) dst[i] = sym("+", {dst[i], numT(v[i], n + " " + "xyz"[i])});
      return self;
    });
  }
  std::string h = didYouMean(n, {"name", "head", "tail", "parent", "length", "rotate", "move"});
  throw ScriptError("osso não tem o atributo '" + n + "'", 0, h.empty() ? "use rotate(x, y, z) ou move(x, y, z)" : h);
}

std::shared_ptr<Bone> Skeleton::find(const std::string &n) const {
  for (auto &b : bones)
    if (b->name == n) return b;
  return nullptr;
}

std::string Skeleton::describe() const { return "<esqueleto " + name + " com " + std::to_string(bones.size()) + " ossos>"; }

ShapeP Skeleton::debugShape(const Value &color, const Value &r) {
  std::vector<ShapeP> parts;
  for (auto &b : bones) {
    V3 t = b->tail();
    double len = std::hypot(t[0] - b->head[0], t[1] - b->head[1], t[2] - b->head[2]);
    double rr = r.isNone() ? std::max(0.006, len * 0.06) : r.n();
    auto seg = segmentShape(b->head, t, rr);
    auto junta = translate(mkShape("sphere", {{"r", rr * 1.7}}), b->head);
    parts.push_back(mkShape("bound", {{"bone", Value(b)}}, {unionOf({seg, junta})}));
  }
  auto c = parseColor(color);
  return mkShape("material", {{"color", nums({c[0], c[1], c[2]})}, {"rough", 0.4}, {"metal", Value()}, {"glow", 0.3}, {"tex", Value()}}, {unionOf(parts)});
}

Value Skeleton::attr(const std::string &n) {
  auto self = std::static_pointer_cast<Skeleton>(shared_from_this());
  if (n == "name") return name;
  if (n == "bones") {
    std::vector<Value> out(bones.begin(), bones.end());
    return list(out);
  }
  auto names = [self] {
    std::vector<std::string> out;
    for (auto &b : self->bones) out.push_back(b->name);
    return out;
  };
  if (n == "bone")
    return native("bone", {"name", "head", "tail=None", "parent=None"}, [self, names](const Args &a, const Node *) -> Value {
      std::string nm = str(a["name"]);
      if (self->find(nm)) throw ScriptError("já existe um osso '" + nm + "'");
      std::shared_ptr<Bone> parent;
      const Value &pv = a["parent"];
      if (pv.isStr()) {
        parent = self->find(pv.s());
        if (!parent) throw ScriptError("osso pai '" + pv.s() + "' não existe", 0, didYouMean(pv.s(), names()));
      } else if (!pv.isNone()) {
        parent = pv.as<Bone>();
        if (!parent || parent->skel != self.get()) throw ScriptError("parent deve ser um osso deste esqueleto");
      }
      auto b = std::make_shared<Bone>();
      b->skel = self.get();
      b->name = nm;
      b->head = vec3(a["head"], "head");
      if (!a["tail"].isNone()) { b->hasTail = true; b->tailSpec = vec3(a["tail"], "tail"); }
      b->parent = parent;
      if (parent) parent->children.push_back(b.get());
      self->bones.push_back(b);
      return b;
    });
  if (n == "get")
    return native("get", {"name"}, [self, names](const Args &a, const Node *) -> Value {
      auto b = self->find(str(a["name"]));
      if (!b) throw ScriptError("osso '" + str(a["name"]) + "' não existe", 0, didYouMean(str(a["name"]), names()));
      return b;
    });
  if (n == "debug")
    return native("debug", {"color=\"yellow\"", "r=None"}, [self](const Args &a, const Node *) {
      return Value(self->debugShape(a["color"], a["r"].isNone() ? Value() : Value(num(a["r"], "r"))));
    });
  std::string h = didYouMean(n, {"name", "bones", "bone", "get", "debug"});
  throw ScriptError("esqueleto não tem o atributo '" + n + "'", 0, h.empty() ? "use bone(nome, head, parent=...)" : h);
}

Builtins rigBuiltins(Interp &it) {
  Scene *sc = &it.scene;
  return {
      {"skeleton", native("skeleton", {"name=\"rig\""}, [](const Args &a, const Node *) {
         auto s = std::make_shared<Skeleton>();
         s->name = str(a["name"]);
         return Value(s);
       })},
      {"animation", native("animation", {"duration=4", "fps=30"}, [sc](const Args &a, const Node *) {
         sc->anim = rec({{"duration", num(a["duration"], "duration")}, {"fps", num(a["fps"], "fps")}});
         return Value();
       })},
  };
}

static ShapeP poseBone(ShapeP node, const Bone &b) {
  bool any = std::any_of(b.angles.begin(), b.angles.end(), [](const Value &a) { return a.isExpr() || a.n() != 0; });
  if (any) {
    M3 m = rotMatrix(val0(b.angles[0]), val0(b.angles[1]), val0(b.angles[2]));
    Props props{{"m", nums9(m)}};
    if (std::any_of(b.angles.begin(), b.angles.end(), [](const Value &a) { return a.isExpr(); })) props.set("angles", list(b.angles));
    node = aroundPivot(node, b.head, [&](const ShapeP &q) { return mkShape("rotate", props, {q}); });
  }
  return translate(node, b.offset);
}

std::vector<ShapeP> resolveRig(const std::vector<ShapeP> &shapes) {
  std::map<const Shape *, bool> hb;
  std::function<bool(const Shape &)> hasBound = [&](const Shape &s) {
    auto it = hb.find(&s);
    if (it != hb.end()) return it->second;
    bool r = s.kind == "bound" || std::any_of(s.children.begin(), s.children.end(), [&](auto &c) { return hasBound(*c); });
    return hb[&s] = r;
  };
  std::function<ShapeP(const ShapeP &)> res = [&](const ShapeP &s) -> ShapeP {
    if (!hasBound(*s)) return s;
    if (s->kind == "bound") {
      ShapeP node = res(s->children[0]);
      for (auto b = s->props["bone"].as<Bone>(); b; b = b->parent) node = poseBone(node, *b);
      return node;
    }
    std::vector<ShapeP> kids;
    for (auto &c : s->children) kids.push_back(res(c));
    return mkShape(s->kind, s->props, kids);
  };
  std::vector<ShapeP> out;
  for (auto &s : shapes) out.push_back(res(s));
  return out;
}

std::vector<std::shared_ptr<Bone>> collectBones(const std::vector<ShapeP> &shapes) {
  std::vector<std::shared_ptr<Bone>> set;
  std::function<void(const Shape &)> visit = [&](const Shape &s) {
    if (s.kind == "bound")
      for (auto b = s.props["bone"].as<Bone>(); b; b = b->parent)
        if (std::find(set.begin(), set.end(), b) == set.end()) set.push_back(b);
    for (auto &c : s.children) visit(*c);
  };
  for (auto &s : shapes) visit(*s);
  std::vector<std::shared_ptr<Bone>> out;
  std::function<void(const std::shared_ptr<Bone> &)> add = [&](const std::shared_ptr<Bone> &b) {
    if (std::find(out.begin(), out.end(), b) != out.end()) return;
    if (b->parent) add(b->parent);
    out.push_back(b);
  };
  for (auto &b : set) add(b);
  return out;
}

}  // namespace tdi
