// Port de tokenize() do parser.js.
#include "lexer.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <set>

#include "error.h"

namespace tdi {

static const std::set<std::string> KEYWORDS = {
    "def", "return", "for", "in", "if", "elif", "else", "while", "and", "or", "not",
    "True", "False", "None", "pass", "break", "continue", "lambda", "is",
};
static const char *OPS2[] = {"**", "//", "==", "!=", "<=", ">=", "+=", "-=", "*=", "/=", "->"};
static const char *OPS1 = "()[]{},:.+-*/%<>=|&^~@;";

// decodifica o ponto de código UTF-8 em s[i]; n recebe quantos bytes ele ocupa
static unsigned codepoint(const std::string &s, size_t i, int &n) {
  unsigned char c = s[i];
  n = 1;
  if (c < 0x80) return c;
  int extra = c >= 0xF0 ? 3 : c >= 0xE0 ? 2 : c >= 0xC0 ? 1 : 0;
  unsigned cp = c & (0x3F >> extra);
  for (int k = 1; k <= extra && i + k < s.size(); k++) cp = cp << 6 | (s[i + k] & 0x3F);
  n = 1 + extra;
  return cp;
}

// aproximação de \p{L} / \p{N} fora do ASCII: letras acentuadas, grego, cirílico, CJK...;
// exclui × ÷, pontuação e símbolos gerais (U+2000–U+2BFF, U+3000–U+303F)
static bool uniLetter(unsigned cp) {
  if (cp < 0xC0 || cp == 0xD7 || cp == 0xF7) return false;
  if (cp >= 0x2000 && cp <= 0x2BFF) return false;
  if (cp >= 0x3000 && cp <= 0x303F) return false;
  return true;
}
static bool isDigit(char c) { return c >= '0' && c <= '9'; }
static bool nameStart(const std::string &s, size_t i, int &n) {
  unsigned cp = codepoint(s, i, n);
  return (cp < 0x80 && (std::isalpha((int)cp) || cp == '_')) || uniLetter(cp);
}
static bool nameChar(const std::string &s, size_t i, int &n) {
  unsigned cp = codepoint(s, i, n);
  return (cp < 0x80 && (std::isalnum((int)cp) || cp == '_')) || uniLetter(cp);
}

// mesmo recorte do regex do JS: \d[\d_]*\.?[\d_]* | \.\d[\d_]*, e expoente opcional
static size_t numberLen(const std::string &s, size_t i) {
  size_t j = i;
  auto run = [&] { while (j < s.size() && (isDigit(s[j]) || s[j] == '_')) j++; };
  if (s[j] == '.') { j++; run(); }
  else {
    j++;
    run();
    if (j < s.size() && s[j] == '.') { j++; run(); }
  }
  if (j < s.size() && (s[j] == 'e' || s[j] == 'E')) {
    size_t k = j + 1;
    if (k < s.size() && (s[k] == '+' || s[k] == '-')) k++;
    if (k < s.size() && isDigit(s[k])) {
      while (k < s.size() && isDigit(s[k])) k++;
      j = k;
    }
  }
  return std::min(j - i, (size_t)64);
}

std::vector<Token> tokenize(std::string in) {
  std::string src;
  src.reserve(in.size());
  for (size_t k = 0; k < in.size(); k++) {
    if (in[k] == '\r') { src += '\n'; if (k + 1 < in.size() && in[k + 1] == '\n') k++; }
    else if (in[k] == '\t') src += "    ";
    else src += in[k];
  }
  std::vector<Token> toks;
  std::vector<int> indents{0};
  size_t i = 0;
  int line = 1, depth = 0;
  bool atLineStart = true;
  auto at = [&](size_t k) { return k < src.size() ? src[k] : '\0'; };
  auto push = [&](Tok t, std::string v = {}, double num = 0) { toks.push_back({t, std::move(v), num, line}); };

  while (i < src.size()) {
    if (atLineStart && depth == 0) {
      int col = 0;
      while (at(i) == ' ') { col++; i++; }
      if (i >= src.size()) break;
      if (src[i] == '\n' || src[i] == '#') {
        while (i < src.size() && src[i] != '\n') i++;
        if (at(i) == '\n') { i++; line++; }
        continue;
      }
      atLineStart = false;
      if (col > indents.back()) {
        indents.push_back(col);
        push(Tok::Indent);
      } else {
        while (col < indents.back()) { indents.pop_back(); push(Tok::Dedent); }
        if (col != indents.back()) throw ScriptError("indentação inconsistente", line, "use sempre 4 espaços por nível");
      }
    }

    char c = src[i];
    if (c == '\n') {
      if (depth == 0) { push(Tok::Newline); atLineStart = true; }
      i++; line++;
      continue;
    }
    if (c == ' ') { i++; continue; }
    if (c == '#') { while (i < src.size() && src[i] != '\n') i++; continue; }
    if (c == '\\' && at(i + 1) == '\n') { i += 2; line++; continue; }

    if (isDigit(c) || (c == '.' && isDigit(at(i + 1)))) {
      size_t n = numberLen(src, i);
      std::string m;
      for (size_t k = i; k < i + n; k++) if (src[k] != '_') m += src[k];
      push(Tok::Num, {}, std::strtod(m.c_str(), nullptr));
      i += n;
      continue;
    }

    bool isStrStart = c == '"' || c == '\'';
    bool isFStr = (c == 'f' || c == 'F') && (at(i + 1) == '"' || at(i + 1) == '\'');
    if (isStrStart || isFStr) {
      if (isFStr) i++;
      char q = src[i];
      bool triple = src.compare(i, 3, std::string(3, q)) == 0;
      std::string end = triple ? std::string(3, q) : std::string(1, q);
      i += end.size();
      std::string s;
      int startLine = line;
      while (true) {
        if (i >= src.size()) throw ScriptError("texto (string) sem fechar aspas", startLine);
        if (src.compare(i, end.size(), end) == 0) { i += end.size(); break; }
        char ch = src[i];
        if (ch == '\n') {
          if (!triple) throw ScriptError("texto (string) sem fechar aspas", startLine);
          line++;
        }
        if (ch == '\\' && i + 1 < src.size()) {
          char e = src[i + 1];
          switch (e) {
            case 'n': s += '\n'; break;
            case 't': s += '\t'; break;
            case '\\': case '\'': case '"': s += e; break;
            default: s += '\\'; s += e;
          }
          i += 2;
          continue;
        }
        s += ch;
        i++;
      }
      push(isFStr ? Tok::FStr : Tok::Str, s);
      continue;
    }

    int n;
    if (nameStart(src, i, n)) {
      size_t j = i + n;
      while (j < src.size() && nameChar(src, j, n)) j += n;
      std::string word = src.substr(i, j - i);
      push(KEYWORDS.count(word) ? Tok::Kw : Tok::Name, word);
      i = j;
      continue;
    }

    bool two = false;
    for (const char *op : OPS2)
      if (src.compare(i, 2, op) == 0) { push(Tok::Op, op); i += 2; two = true; break; }
    if (two) continue;
    if (c && std::strchr(OPS1, c)) {
      if (c == '(' || c == '[' || c == '{') depth++;
      if (c == ')' || c == ']' || c == '}') depth = std::max(0, depth - 1);
      push(Tok::Op, std::string(1, c));
      i++;
      continue;
    }
    codepoint(src, i, n);
    throw ScriptError("caractere inesperado '" + src.substr(i, n) + "'", line);
  }
  if (!toks.empty() && toks.back().type != Tok::Newline) push(Tok::Newline);
  while (indents.size() > 1) { indents.pop_back(); push(Tok::Dedent); }
  push(Tok::Eof);
  return toks;
}

}  // namespace tdi
