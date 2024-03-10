#include <stdio.h>
#include <string.h>
#include "cyber.h"

// Compile this program with a C compiler. `zig cc` is used here as an example.
// zig cc main.c -I ../../src/include ../../zig-out/lib/libcyber.a -o main

#define STR(s) ((CsStr){ s, strlen(s) })

void print(CsVM* vm, CsStr str) {
    printf("My print: %.*s\n", (int)str.len, str.buf);
}

int main() {
    CsVM* vm = csCreate();
    csSetPrinter(vm, print);

    CsStr src = STR(
        "var a = 1\n"
        "print(a + 2)\n"
    );
    CsValue val;
    int res = csEval(vm, src, &val);
    if (res == CS_SUCCESS) {
        printf("Success!\n");
        csRelease(vm, val);
    } else { 
        CsStr s = csNewLastErrorSummary(vm);
        printf("%.*s\n", (int)s.len, s.buf);
        csFreeStr(vm, s);
    }
    csDestroy(vm);
    return 0;
}