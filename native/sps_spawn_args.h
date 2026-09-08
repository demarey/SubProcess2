/*
 * sps_spawn_args.h
 *
 * Splits the NUL-separated argument blob (see sps_spawn.h) into a
 * NULL-terminated argv array, using a single allocation so it can be freed
 * with a single free().
 */

#ifndef SPS_SPAWN_ARGS_H
#define SPS_SPAWN_ARGS_H

#include <stddef.h>

/* Build a NULL-terminated char** from the NUL-separated blob of the given
 * length (see sps_spawn.h). The blob may contain embedded NULs, so blob_len
 * must be supplied explicitly. Returns 0 on success (sets *out_argv),
 * -1 on failure. */
int sps_split_args (const char *blob, size_t blob_len, char ***out_argv);

/* Free the array returned by sps_split_args. */
void sps_free_args (char **argv);

#endif
