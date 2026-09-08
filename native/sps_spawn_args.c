#include "sps_spawn_args.h"

#include <stdlib.h>
#include <string.h>

int
sps_split_args (const char *blob, size_t blob_len, char ***out_argv)
{
  char **argv;
  char *data;
  size_t count;
  size_t i;
  size_t slot;

  if (blob == NULL || out_argv == NULL)
    return -1;

  *out_argv = NULL;

  /* A token starts at index 0 or just after a NUL, and is a non-NUL run.
     The terminating NUL of the last token is the blob's final byte, so this
     index scan never reads past blob_len. */
  count = 0;
  for (i = 0; i < blob_len; i++)
    if (blob[i] != '\0' && (i == 0 || blob[i - 1] == '\0'))
      count++;

  if (count == 0)
    return -1;                                     /* no program specified */

  /* Single allocation: the pointer array followed by the token data block
     (blob_len bytes + a trailing NUL so entries remain valid C strings). */
  argv = (char **) malloc ((count + 1) * sizeof (char *) + blob_len + 1);
  if (argv == NULL)
    return -1;

  data = (char *) (argv + (count + 1));
  memcpy (data, blob, blob_len);
  data[blob_len] = '\0';

  slot = 0;
  for (i = 0; i < blob_len; i++)
    if (data[i] != '\0' && (i == 0 || data[i - 1] == '\0'))
      argv[slot++] = data + i;
  argv[slot] = NULL;

  *out_argv = argv;
  return 0;
}

void
sps_free_args (char **argv)
{
  free (argv);
}
