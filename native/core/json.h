// JSON mínimo: lê os golden files (tests/golden/) e compara com o que o core em C++ produz.
#pragma once
#include <string>
#include <utility>
#include <vector>

namespace tdi {

struct Json {
  enum Type { Null, Bool, Num, Str, Arr, Obj } t = Null;
  bool b = false;
  double n = 0;
  std::string s;
  std::vector<Json> a;
  std::vector<std::pair<std::string, Json>> o;  // ordem de inserção; dump() ordena as chaves

  Json() = default;
  Json(std::nullptr_t) {}
  Json(bool v) : t(Bool), b(v) {}
  Json(double v) : t(Num), n(v) {}
  Json(int v) : t(Num), n(v) {}
  Json(const char *v) : t(Str), s(v) {}
  Json(std::string v) : t(Str), s(std::move(v)) {}
  static Json array() { Json j; j.t = Arr; return j; }
  static Json object() { Json j; j.t = Obj; return j; }

  Json &set(const std::string &k, Json v);  // objeto: define ou troca a chave
  Json &push(Json v) { a.push_back(std::move(v)); return a.back(); }
  const Json *get(const std::string &k) const;
  const Json &operator[](const std::string &k) const;
  bool isNull() const { return t == Null; }

  static Json parse(const std::string &text);  // lança std::runtime_error
  std::string dump() const;
};

// compara com tolerância relativa nos números; devolve "" se iguais, senão o caminho da 1ª diferença
std::string jsonDiff(const Json &got, const Json &want, double tol = 1e-7, const std::string &path = "$");

}  // namespace tdi
