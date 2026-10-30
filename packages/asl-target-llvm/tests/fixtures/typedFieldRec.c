/* Test-only fixture for nativeRunTest's testTypedFields (plan SH unit M4b-2).
 * Linked with the LLVM IR asl-target-llvm/ssa emits (emitLlvmModule, no @main wrapper) for
 * nativeRunTest's typedFieldSource and with libaslrt.a, it builds records on the host side
 * with asl_alloc and interned keys, as the VM or a host builtin may, and hands them to the compiled typed
 * functions getY (Point -> Int64, a fused opField-into-opUnbox read) and nameOf
 * (Person -> String, a plain Val read). The source declares Point (x y) and Person
 * (age name); here each schema is built once in declared order and once with its keys
 * swapped, so a static slot read that skipped the keys[i] check would return the other field.
 * getY and nameOf are tailcc in the IR; each takes one %Val (two integer registers) and
 * nothing travels on the stack, where tailcc and the C convention assign the same registers.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct { uint32_t tag; uint32_t aux; union { int64_t i; double f; void *o; } u; } Val; /* asl/host/src/value.h */
typedef struct { uint32_t size; uint8_t type, mark, perm, classIdx; int schema; int n; int *keys; Val v[]; } Rec; /* value.h Obj + Rec */

void asl_rt_init(void);
void *asl_alloc(int type, size_t bytes);
int intern(const char *s, size_t n);
Val mkStr(const char *s, size_t n);
static Val intVal(int64_t i) { Val v = {2, 0, {.i = i}}; return v; } /* T_INT, as compiled code boxes an Int inline */

/* a two-field record of schema with keys in the given order; ids lives as long as the record (value.h Rec.keys) */
static Val record(const char *schema, const char *const *keys, int *ids, const Val *vals) {
  for (int i = 0; i < 2; i++) ids[i] = intern(keys[i], strlen(keys[i]));
  Rec *r = asl_alloc(2 /* O_REC */, sizeof(Rec) + 2 * sizeof(Val));
  r->schema = intern(schema, strlen(schema)); r->n = 2; r->keys = ids;
  for (int i = 0; i < 2; i++) r->v[i] = vals[i];
  Val v = {7 /* T_REC */, 0, {.o = r}};
  return v;
}

int64_t getY(Val p);
Val nameOf(Val p);

static const char *sameVal(Val got, Val want) {
  return got.tag == want.tag && got.u.o == want.u.o ? "same" : "other";
}

int main(void) {
  asl_rt_init();
  const char *const declaredPoint[] = {"x", "y"};
  const char *const swappedPoint[] = {"y", "x"};
  Val orderedXY[] = {intVal(1), intVal(2)};
  Val swappedYX[] = {intVal(20), intVal(10)};
  static int orderedPointIds[2], swappedPointIds[2], orderedPersonIds[2], swappedPersonIds[2];
  Val ordered = record("Point", declaredPoint, orderedPointIds, orderedXY);
  Val swapped = record("Point", swappedPoint, swappedPointIds, swappedYX);
  const char *const declaredPerson[] = {"age", "name"};
  const char *const swappedPerson[] = {"name", "age"};
  Val ada = mkStr("Ada", 3);
  Val grace = mkStr("Grace", 5);
  Val orderedAN[] = {intVal(36), ada};
  Val swappedNA[] = {grace, intVal(45)};
  Val orderedPerson = record("Person", declaredPerson, orderedPersonIds, orderedAN);
  Val swappedPersonRec = record("Person", swappedPerson, swappedPersonIds, swappedNA);
  printf("orderedY=%lld swappedY=%lld orderedName=%s swappedName=%s\n",
         (long long)getY(ordered), (long long)getY(swapped),
         sameVal(nameOf(orderedPerson), ada), sameVal(nameOf(swappedPersonRec), grace));
  return 0;
}
