// Registro dos módulos que não são o núcleo: âncoras, padrões e as bibliotecas de geradores.
#include "anchor.h"
#include "interp.h"
#include "pattern.h"

namespace tdi {
namespace kit {
Builtins grassBuiltins(Interp &);
Builtins plantBuiltins(Interp &);
Builtins treeBuiltins(Interp &);
Builtins peopleBuiltins(Interp &);
Builtins vehicleBuiltins(Interp &);
}  // namespace kit

void registerExtraMethods() {
  static bool done = false;
  if (done) return;
  done = true;
  registerAnchorMethods();
  registerPatternMethods();
}

Builtins libBuiltins(Interp &it) {
  Builtins b;
  for (auto f : {kit::grassBuiltins, kit::plantBuiltins, kit::treeBuiltins, kit::peopleBuiltins, kit::vehicleBuiltins})
    for (auto &x : f(it)) b.push_back(x);
  return b;
}
}  // namespace tdi
