/* asl-host's builtinTables chain, alone in its libaslhost.a member: prelude.c's reference pulls it into asl-host and an
   embedded build */
#include "compile.h"

__attribute__((weak)) const BuiltinTable builtinTables[] = {BUILTIN_TABLES_WITH(gcTestBuiltins, &nGcTestBuiltins)};
__attribute__((weak)) const int nBuiltinTables = (int)(sizeof builtinTables / sizeof builtinTables[0]);
