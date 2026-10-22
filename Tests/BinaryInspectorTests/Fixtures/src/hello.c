// A small executable: initialised data, a large zero-filled array (so __DATA's vmsize is
// larger than its filesize), a local function and an external call.
#include <stdio.h>

int counter = 7;
__attribute__((aligned(16))) char scratch[65536];

__attribute__((noinline)) static int twice(int value) { return value * 2; }

int main(int argc, char **argv) {
    scratch[argc] = (char)counter;
    printf("%d %s\n", twice(counter) + scratch[1], argv[0]);
    return 0;
}
