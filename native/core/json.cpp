#include "json.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>

namespace tdi {

Json &Json::set(const std::string &k, Json v) {
  t = Obj;
  for (auto &[key, val] : o)
    if (key == k) return val = std::move(v);
  o.emplace_back(k, std::move(v));
  return o.back().second;
}

const Json *Json::get(const std::string &k) const {
  for (auto &[key, val] : o)
    if (key == k) return &val;
  return nullptr;
}

const Json &Json::operator[](const std::string &k) const {
  static const Json null;
  const Json *v = get(k);
  return v ? *v : null;
}

namespace {
struct Reader {
  const std::string &s;
  size_t i = 0;
  [[noreturn]] void fail(const char *what) { throw std::runtime_error(std::string("JSON: ") + what + " na posição " + std::to_string(i)); }
  void ws() { while (i < s.size() && (s[i] == ' ' || s[i] == '\n' || s[i] == '\r' || s[i] == '\t')) i++; }
  bool lit(const char *w) {
    size_t n = std::char_traits<char>::length(w);
    if (s.compare(i, n, w) != 0) return false;
    i += n;
    return true;
  }
  static void utf8(std::string &out, unsigned cp) {
    if (cp < 0x80) out += char(cp);
    else if (cp < 0x800) { out += char(0xC0 | cp >> 6); out += char(0x80 | (cp & 63)); }
    else if (cp < 0x10000) { out += char(0xE0 | cp >> 12); out += char(0x80 | (cp >> 6 & 63)); out += char(0x80 | (cp & 63)); }
    else { out += char(0xF0 | cp >> 18); out += char(0x80 | (cp >> 12 & 63)); out += char(0x80 | (cp >> 6 & 63)); out += char(0x80 | (cp & 63)); }
  }
  unsigned hex4() {
    if (i + 4 > s.size()) fail("\\u incompleto");
    unsigned v = (unsigned)std::strtoul(s.substr(i, 4).c_str(), nullptr, 16);
    i += 4;
    return v;
  }
  std::string str() {
    if (s[i] != '"') fail("esperado texto");
    i++;
    std::string out;
    while (true) {
      if (i >= s.size()) fail("texto sem fim");
      char c = s[i++];
      if (c == '"') return out;
      if (c != '\\') { out += c; continue; }
      char e = s[i++];
      switch (e) {
        case 'n': out += '\n'; break;
        case 't': out += '\t'; break;
        case 'r': out += '\r'; break;
        case 'b': out += '\b'; break;
        case 'f': out += '\f'; break;
        case 'u': {
          unsigned cp = hex4();
          if (cp >= 0xD800 && cp < 0xDC00 && s.compare(i, 2, "\\u") == 0) {
            i += 2;
            cp = 0x10000 + ((cp - 0xD800) << 10) + (hex4() - 0xDC00);
          }
          utf8(out, cp);
          break;
        }
        default: out += e;
      }
    }
  }
  Json value() {
    ws();
    if (i >= s.size()) fail("fim inesperado");
    char c = s[i];
    if (c == '{') {
      i++;
      Json j = Json::object();
      ws();
      if (s[i] == '}') { i++; return j; }
      while (true) {
        ws();
        std::string k = str();
        ws();
        if (s[i++] != ':') fail("esperado ':'");
        j.o.emplace_back(std::move(k), value());
        ws();
        if (s[i] == ',') { i++; continue; }
        if (s[i++] != '}') fail("esperado '}'");
        return j;
      }
    }
    if (c == '[') {
      i++;
      Json j = Json::array();
      ws();
      if (s[i] == ']') { i++; return j; }
      while (true) {
        j.a.push_back(value());
        ws();
        if (s[i] == ',') { i++; continue; }
        if (s[i++] != ']') fail("esperado ']'");
        return j;
      }
    }
    if (c == '"') return Json(str());
    if (lit("true")) return Json(true);
    if (lit("false")) return Json(false);
    if (lit("null")) return Json();
    char *end = nullptr;
    double v = std::strtod(s.c_str() + i, &end);
    if (end == s.c_str() + i) fail("valor inválido");
    i = end - s.c_str();
    return Json(v);
  }
};

void dumpTo(const Json &j, std::string &out) {
  switch (j.t) {
    case Json::Null: out += "null"; break;
    case Json::Bool: out += j.b ? "true" : "false"; break;
    case Json::Num: {
      char buf[32];
      if (std::isfinite(j.n)) std::snprintf(buf, sizeof buf, "%.17g", j.n);
      else std::snprintf(buf, sizeof buf, "null");
      out += buf;
      break;
    }
    case Json::Str:
      out += '"';
      for (char c : j.s) {
        if (c == '"' || c == '\\') { out += '\\'; out += c; }
        else if (c == '\n') out += "\\n";
        else if (c == '\t') out += "\\t";
        else if ((unsigned char)c < 0x20) { char b[8]; std::snprintf(b, sizeof b, "\\u%04x", c); out += b; }
        else out += c;
      }
      out += '"';
      break;
    case Json::Arr:
      out += '[';
      for (size_t k = 0; k < j.a.size(); k++) { if (k) out += ','; dumpTo(j.a[k], out); }
      out += ']';
      break;
    case Json::Obj: {
      std::vector<const std::pair<std::string, Json> *> kv;
      for (auto &p : j.o) kv.push_back(&p);
      std::sort(kv.begin(), kv.end(), [](auto *x, auto *y) { return x->first < y->first; });
      out += '{';
      for (size_t k = 0; k < kv.size(); k++) {
        if (k) out += ',';
        dumpTo(Json(kv[k]->first), out);
        out += ':';
        dumpTo(kv[k]->second, out);
      }
      out += '}';
      break;
    }
  }
}
}  // namespace

Json Json::parse(const std::string &text) {
  Reader r{text};
  Json j = r.value();
  r.ws();
  if (r.i != text.size()) r.fail("sobra depois do valor");
  return j;
}

std::string Json::dump() const {
  std::string out;
  dumpTo(*this, out);
  return out;
}

std::string jsonDiff(const Json &got, const Json &want, double tol, const std::string &path) {
  auto brief = [](const Json &j) { std::string d = j.dump(); return d.size() > 120 ? d.substr(0, 120) + "…" : d; };
  if (got.t != want.t) return path + ": tipo difere, obtido " + brief(got) + ", esperado " + brief(want);
  switch (got.t) {
    case Json::Null: return "";
    case Json::Bool: return got.b == want.b ? "" : path + ": " + brief(got) + " != " + brief(want);
    case Json::Str: return got.s == want.s ? "" : path + ": " + brief(got) + " != " + brief(want);
    case Json::Num: {
      double d = std::fabs(got.n - want.n), m = std::max(std::fabs(got.n), std::fabs(want.n));
      return d <= tol * std::max(m, 1.0) ? "" : path + ": " + brief(got) + " != " + brief(want);
    }
    case Json::Arr: {
      if (got.a.size() != want.a.size())
        return path + ": tamanho " + std::to_string(got.a.size()) + " != " + std::to_string(want.a.size());
      for (size_t k = 0; k < got.a.size(); k++) {
        std::string d = jsonDiff(got.a[k], want.a[k], tol, path + "[" + std::to_string(k) + "]");
        if (!d.empty()) return d;
      }
      return "";
    }
    case Json::Obj: {
      for (auto &[k, v] : want.o)
        if (!got.get(k)) return path + ": falta a chave '" + k + "'";
      for (auto &[k, v] : got.o) {
        const Json *w = want.get(k);
        if (!w) return path + ": chave a mais '" + k + "'";
        std::string d = jsonDiff(v, *w, tol, path + "." + k);
        if (!d.empty()) return d;
      }
      return "";
    }
  }
  return "";
}

}  // namespace tdi
