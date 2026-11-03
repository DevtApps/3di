#pragma once
#include <string>

#include "ast.h"

namespace tdi {

Block parse(const std::string &src);  // lança ScriptError

}  // namespace tdi
