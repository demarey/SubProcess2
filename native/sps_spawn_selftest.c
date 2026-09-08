/*
 * sps_spawn_selftest.c
 *
 * Validates the sps_* shim end-to-end without GLib:
 *   - creates the three pipes with sps_pipe(),
 *   - spawns <this-exe> --child-echo through sps_spawn(),
 *   - writes "hello stdin" to the child's stdin with sps_write() and closes it,
 *   - waits for the child with sps_wait() and checks its exit code,
 *   - reads the child's stdout with sps_read() and asserts it echoes the input.
 *
 * Because the shim owns every platform-specific detail, this test is identical
 * on Unix and Windows.
 */

#include "sps_spawn.h"

#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#  include <wchar.h>
#else
#  include <sys/wait.h>
#endif

static int
run_child_echo (void)
{
  int c;
  while ((c = fgetc (stdin)) != EOF)
    fputc (c, stdout);
  fflush (stdout);
  return 0;
}

/* Wait for (and reap) the child and answer its decoded exit code. */
static int
sps_selftest_wait (intptr_t pid, int *out_exit)
{
  int status = 0;
  if (sps_wait (pid, 1, &status) != 1)
    return -1;
#if defined(_WIN32)
  /* Unlike Unix we cannot tell a signal death from a normal one; the encoded
     status is (code << 8), so the low 8 bits are recovered directly. */
  *out_exit = (status >> 8) & 0xFF;
#else
  if (WIFEXITED (status))
    *out_exit = WEXITSTATUS (status);
  else
    *out_exit = -1;
#endif
  return 0;
}

static int
sps_selftest_run_parent (const char *self_path)
{
  static const char payload[] = "hello stdin";
  sps_fd_t stdin_child_fd, stdin_parent_fd;
  sps_fd_t stdout_child_fd, stdout_parent_fd;
  sps_fd_t stderr_child_fd, stderr_parent_fd;
  const char *argv[3];
  char errbuf[512];
  intptr_t pid;
  char buf[4096];
  long total = 0;
  int exit_code = 0;
  int ok = 1;

  if (sps_pipe (SPS_PIPE_STDIN, &stdin_parent_fd, &stdin_child_fd) != 0)
    return 2;
  if (sps_pipe (SPS_PIPE_STDOUT, &stdout_parent_fd, &stdout_child_fd) != 0)
    return 2;
  if (sps_pipe (SPS_PIPE_STDERR, &stderr_parent_fd, &stderr_child_fd) != 0)
    return 2;

  argv[0] = self_path;
  argv[1] = "--child-echo";
  argv[2] = NULL;

  /* NUL-separated blob: "prog\0--child-echo\0". */
  {
    char args_blob[2048];
    size_t n = 0;
    for (int i = 0; argv[i] != NULL; i++)
      {
        size_t len = strlen (argv[i]);
        memcpy (args_blob + n, argv[i], len + 1);
        n += len + 1;
      }

    pid = sps_spawn (stdin_child_fd, stdout_child_fd, stderr_child_fd,
                     args_blob, n, NULL, errbuf, sizeof errbuf);
  }
  if (pid <= 0)
    {
      fprintf (stderr, "FAIL spawn: %s\n", errbuf);
      return 2;
    }

  /* Close the child-facing copies in the parent (the caller owns this step,
     not the shim); only then can the parent's read ends see EOF. */
  sps_close (stdin_child_fd);
  sps_close (stdout_child_fd);
  sps_close (stderr_child_fd);

  /* Write the payload to the child's stdin, then close it (delivers EOF). */
  {
    size_t written = 0;
    while (written < sizeof payload - 1)
      {
        long n = sps_write (stdin_parent_fd, payload + written,
                            sizeof payload - 1 - written);
        written += (size_t) n;
      }
  }
  sps_close (stdin_parent_fd);

  if (sps_selftest_wait (pid, &exit_code) != 0)
    ok = 0;

  /* Read the child's stdout until EOF. */
  while (total < (long) sizeof buf)
    {
      long n = sps_read (stdout_parent_fd, buf + total,
                         sizeof buf - (size_t) total);
      if (n <= 0)
        break;
      total += n;
    }

  ok = ok && exit_code == 0;
  ok = ok && total == (long) sizeof payload - 1
          && memcmp (buf, payload, sizeof payload - 1) == 0;

  printf ("%s exit=%d echoed=\"%.*s\"\n", ok ? "PASS" : "FAIL",
          exit_code, (int) total, buf);

  sps_close (stdout_parent_fd);
  sps_close (stderr_parent_fd);

  return ok ? 0 : 2;
}

/* Spawning a nonexistent program must yield a negated error number and a
 * populated errbuf rather than a child identifier. */
static int
sps_selftest_run_error (void)
{
  static const char blob[] = "/no/such/program_xyz";
  sps_fd_t unused[3] = { (sps_fd_t) 0, (sps_fd_t) 1, (sps_fd_t) 2 };
  char errbuf[512];
  intptr_t pid;

  pid = sps_spawn (unused[0], unused[1], unused[2],
                   blob, sizeof blob - 1, NULL, errbuf, sizeof errbuf);
  if (pid > 0)
    {
      printf ("FAIL error-path: unexpected pid %ld\n", (long) pid);
      return 2;
    }
  printf ("PASS error-path pid=%ld errbuf=\"%s\"\n", (long) pid, errbuf);
  return 0;
}

int
main (int argc, char **argv)
{
  int result;
  if (argc > 1 && strcmp (argv[1], "--child-echo") == 0)
    return run_child_echo ();
  result = sps_selftest_run_parent (argv[0]);
  if (result != 0)
    return result;
  return sps_selftest_run_error ();
}
