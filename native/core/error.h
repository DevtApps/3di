// Erro do script com linha e dica, como o ScriptError do JS (mensagens em pt-BR).
#pragma once
#include <stdexcept>
#include <string>

namespace tdi {

struct ScriptError : std::runtime_error {
  int line = 0;  // 0: sem linha
  std::string hint;
  ScriptError(const std::string &msg, int line = 0, std::string hint = {})
      : std::runtime_error(msg), line(line), hint(std::move(hint)) {}
  std::string str() const {
    return (line ? "linha " + std::to_string(line) + ": " : std::string()) + what() + (hint.empty() ? "" : "\n  dica: " + hint);
  }
};

}  // namespace tdi
