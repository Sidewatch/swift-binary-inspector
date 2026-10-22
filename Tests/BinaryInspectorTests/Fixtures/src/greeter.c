// A small dylib with an install name, an rpath and weak, re-exported and upward links.
#include <zlib.h>

const char *greeting(void) { return "hello"; }

unsigned long checksum(const unsigned char *bytes, unsigned length) { return adler32(1, bytes, length); }
