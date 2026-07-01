/* Minimal public-domain SHA-256 for the benchmark harness (C/C++ targets).
 * sha256_hex(data, len, out) writes a 64-char lowercase hex digest + NUL. */
#ifndef SOFAB_ARENA_SHA256_H
#define SOFAB_ARENA_SHA256_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
void sha256_hex(const void *data, size_t len, char out[65]);
#ifdef __cplusplus
}
#endif
#endif
