#pragma once
#include <string>
#include <vector>

namespace tdi {

enum class Tok { Name, Kw, Num, Str, FStr, Op, Newline, Indent, Dedent, Eof };

struct Token {
  Tok type;
  std::string value;  // NAME/KW/OP/STR/FSTR
  double num = 0;     // NUM
  int line = 0;
};

std::vector<Token> tokenize(std::string src);  // lança ScriptError

}  // namespace tdi
