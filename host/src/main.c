/* asl-host CLI entry point. Verb implementations and dispatch live in libaslhost.a. */
#include "compile.h"
#include <signal.h>

int cmdHostVerb(int argc, char **argv);

int main(int argc, char **argv) {
  signal(SIGPIPE, SIG_IGN);
  gcInit();
  vmInit();
  return cmdHostVerb(argc, argv);
}
