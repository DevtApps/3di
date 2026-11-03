// Formas imutáveis, caixas envolventes, métodos e construtores (port de shapes.js).
#pragma once
#include <array>
#include <functional>
#include <map>
#include <optional>
#include <string>
#include <vector>

#include "value.h"

namespace tdi {

constexpr double INF = 1e4;
using V3 = std::array<double, 3>;
using M3 = std::array<double, 9>;

struct BBox {
  V3 min, max;
};

// propriedades com ordem de inserção e chaves de texto (o objeto `props` do JS)
struct Props {
  std::vector<std::pair<std::string, Value>> kv;
  Props() = default;
  Props(std::initializer_list<std::pair<std::string, Value>> l) : kv(l) {}
  const Value &operator[](const std::string &k) const;
  bool has(const std::string &k) const;
  Props &set(const std::string &k, Value v);
  double num(const std::string &k) const;  // número (ou valor em t = 0)
  std::vector<double> vec(const std::string &k) const;
  V3 v3(const std::string &k) const;
  M3 m3(const std::string &k) const;
  Json plain() const;
};

// objeto JS simples ({kind, c2, size...}): só campos
struct Rec : Object {
  Props f;
  Rec() = default;
  Rec(Props p) : f(std::move(p)) {}
  Json plain() const override { return f.plain(); }
  Value attr(const std::string &name) override;
};
inline Value rec(Props p) { return Value(std::make_shared<Rec>(std::move(p))); }

struct Shape {
  std::string kind;
  Props props;
  std::vector<ShapeP> children;

  Shape(std::string kind, Props props = {}, std::vector<ShapeP> children = {})
      : kind(std::move(kind)), props(std::move(props)), children(std::move(children)) {}
  const BBox &bbox() const;
  bool selfAnimated() const;
  bool animated() const;
  int leaves() const;
  std::string describe() const;
  Json plainTree() const;  // plain() do golden.mjs para uma Shape

 private:
  mutable std::optional<BBox> bb_;
  mutable int leaves_ = -1, anim_ = -1;
};

inline ShapeP mkShape(std::string kind, Props props = {}, std::vector<ShapeP> children = {}) {
  return std::make_shared<Shape>(std::move(kind), std::move(props), std::move(children));
}

// ---------- caixas ----------
bool isFiniteBB(const BBox &b);
V3 center(const BBox &b);
V3 size(const BBox &b);
BBox unionBB(const std::vector<BBox> &list);
std::array<V3, 8> corners(const BBox &b);
BBox fromPoints(const std::vector<V3> &pts);
BBox transformedBBox(const Shape &s, const M3 &m, const V3 &t);
V3 mulMV(const M3 &m, const V3 &v);
M3 mul3(const M3 &a, const M3 &b);
M3 rotMatrix(double ax, double ay, double az);
extern const M3 IDENT;

// ---------- valores <-> vetores ----------
Value nums(const std::vector<double> &v);
Value nums3(const V3 &v);
Value nums9(const M3 &m);
std::vector<double> toVec(const Value &v);

// ---------- construtores ----------
ShapeP translate(const ShapeP &s, std::vector<Value> v);  // v: números ou expressões (time)
ShapeP translate(const ShapeP &s, const V3 &v);
ShapeP aroundPivot(const ShapeP &s, const V3 &c, const std::function<ShapeP(const ShapeP &)> &wrap);
ShapeP segmentShape(const V3 &a, const V3 &b, double r);
ShapeP roundCone(const V3 &a, const V3 &b, double r1, double r2);
ShapeP unionOf(const std::vector<ShapeP> &list, double k = 0);
ShapeP subtractOf(const ShapeP &a, const std::vector<ShapeP> &others, const Value &smooth = 0.0);
ShapeP intersectOf(const std::vector<ShapeP> &list, const Value &smooth = 0.0);
std::vector<ShapeP> flatten(const std::vector<Value> &values, const std::string &what);
void needFinite(const Shape &s, const std::string &what);
std::array<double, 3> parseColor(const Value &v);
ShapeP material(const ShapeP &s, const Args &a);
int axisIndex(const Value &v, const std::string &what);
std::string jsLower(const std::string &s);  // toLowerCase (ASCII e Latin-1)

// ---------- métodos e atributos ----------
using ShapeMethod = std::function<Value(const ShapeP &, const Args &)>;
struct MethodDef {
  std::vector<std::string> params;
  ShapeMethod fn;
};
std::vector<std::pair<std::string, MethodDef>> &shapeMethods();  // ordem de registro (para as dicas)
void addMethod(const std::string &name, std::vector<std::string> params, ShapeMethod fn);
std::vector<std::pair<std::string, std::function<Value(const ShapeP &)>>> &shapeAttrs();
Value getShapeAttr(const ShapeP &s, const std::string &name);
Value callMethod(const std::string &name, const ShapeP &s, const Args &a);  // METHODS[name][1](s, a)
Value shapeBinary(const std::string &op, const Value &a, const Value &b);

// alvo de layout (on/under/beside/attach): uma forma, ou só uma caixa (escopos)
struct Boxed {
  ShapeP shape;
  BBox bb;
};
Boxed asShape(const Value &v, const std::string &what);

// ---------- cena ----------
struct Scene {
  std::vector<ShapeP> shapes;
  Value camera, sun, sky, fog, light, anim;
};
using Builtins = std::vector<std::pair<std::string, Value>>;
Builtins shapeBuiltins(Scene &scene);

struct Part {
  std::string name;
  BBox bbox;
};
std::vector<Part> collectParts(const std::vector<ShapeP> &shapes);

extern const std::vector<std::pair<std::string, std::string>> COLORS;
extern const std::vector<std::pair<std::string, int>> TEXTURES;

}  // namespace tdi
