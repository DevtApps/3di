// Módulos ainda não portados (rig, escopos, curvas, bibliotecas): registram nada por enquanto.
#include "interp.h"

namespace tdi {
Builtins rigBuiltins(Interp &) { return {}; }
Builtins scopeBuiltins(Interp &) { return {}; }
Builtins curveBuiltins(Interp &) { return {}; }
Builtins libBuiltins(Interp &) { return {}; }
void registerExtraMethods() {}
}  // namespace tdi
