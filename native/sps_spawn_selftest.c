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
#  include <windows.h>
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
  long retries = 0;
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

    sps_stdio_spec_t stdio;
    memset (&stdio, 0, sizeof stdio);
    stdio.stdin_mode = SPS_STDIO_PIPE;
    stdio.stdout_mode = SPS_STDIO_PIPE;
    stdio.stderr_mode = SPS_STDIO_PIPE;
    stdio.stdin_fd = stdin_child_fd;
    stdio.stdout_fd = stdout_child_fd;
    stdio.stderr_fd = stderr_child_fd;

    pid = sps_spawn (&stdio, args_blob, n, NULL, errbuf, sizeof errbuf);
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
    int guard = 0;
    while (written < sizeof payload - 1 && guard < 100)
      {
        long n = sps_write (stdin_parent_fd, payload + written,
                            sizeof payload - 1 - written);
        if (n <= 0)
          {
            printf ("  stdin write returned %ld\n", n);
            break;
          }
        written += (size_t) n;
        guard++;
      }
    printf ("  stdin written=%zu\n", written);
  }
  sps_close (stdin_parent_fd);

  if (sps_selftest_wait (pid, &exit_code) != 0)
    ok = 0;

#if defined(_WIN32)
  {
    DWORD avail = 0, total = 0, pending = 0;
    BOOL okp = PeekNamedPipe ((HANDLE) stdout_parent_fd, NULL, 0,
                              &avail, &total, &pending);
    printf ("  probe stdout after wait: ok=%d avail=%lu total=%lu pending=%lu err=%lu\n",
            (int) okp, (unsigned long) avail, (unsigned long) total,
            (unsigned long) pending, (unsigned long) GetLastError ());
  }
#endif

  /* Read the child's stdout and stderr to EOF. sps_read returns -1 when no
     data is available yet (polling mode), so like a real consumer we retry;
     it returns 0 at EOF. Bound the loop so a genuinely silent child cannot
     hang the self-test. */
  {
    while (total < (long) sizeof buf && retries < 50000)
      {
        long n;
        sps_fd_set_nonblocking (stdout_parent_fd);
        n = sps_read (stdout_parent_fd, buf + total,
                      sizeof buf - (size_t) total);
        if (n > 0)
          {
            total += n;
            retries = 0;
          }
        else if (n == 0)
          break;                       /* EOF: all write ends closed */
        else
          retries++;                   /* -1: no data yet; poll again */
      }

    {
      char errout[512];
      long etotal = 0;
      long eretries = 0;
      while (etotal < (long) sizeof errout && eretries < 50000)
        {
          long n = sps_read (stderr_parent_fd, errout + etotal,
                             sizeof errout - (size_t) etotal);
          if (n > 0)
            {
              etotal += n;
              eretries = 0;
            }
          else if (n == 0)
            break;
          else
            eretries++;
        }
      if (etotal > 0)
        printf ("  child stderr: \"%.*s\"\n", (int) etotal, errout);
    }
  }

  ok = ok && exit_code == 0;
  ok = ok && total == (long) sizeof payload - 1
          && memcmp (buf, payload, sizeof payload - 1) == 0;

  printf ("%s exit=%d echoed=\"%.*s\" busy-polls=%ld\n",
          ok ? "PASS" : "FAIL", exit_code, (int) total, buf, retries);

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
  char errbuf[512];
  intptr_t pid;

  sps_stdio_spec_t stdio;
  memset (&stdio, 0, sizeof stdio);
  stdio.stdin_mode = SPS_STDIO_INHERIT;
  stdio.stdout_mode = SPS_STDIO_INHERIT;
  stdio.stderr_mode = SPS_STDIO_INHERIT;

  pid = sps_spawn (&stdio, blob, sizeof blob - 1, NULL, errbuf, sizeof errbuf);
  if (pid > 0)
    {
      printf ("FAIL error-path: unexpected pid %ld\n", (long) pid);
      return 2;
    }
  printf ("PASS error-path pid=%ld errbuf=\"%s\"\n", (long) pid, errbuf);
  return 0;
}

/* Child mode: write a known banner to stdout and stderr, then exit. Used to
 * observe the SILENCE and MERGE output policies. */
static int
run_child_write (void)
{
  static const char out_msg[] = "WRITE-OUT\n";
  static const char err_msg[] = "WRITE-ERR\n";
  sps_write (1, out_msg, sizeof out_msg - 1);
  sps_write (2, err_msg, sizeof err_msg - 1);
  return 0;
}

/* Build a NUL-separated args blob ("self_path\0--child-echo\0...") for the
 * given child mode, into out_blob (out_len bytes available). Answer the blob
 * byte length (excluding the trailing NUL is included as argv terminator). */
static size_t
sps_selftest_build_blob (const char *self_path, const char *child_mode,
                         char *out_blob, size_t out_len)
{
  const char *parts[] = { self_path, child_mode, NULL };
  size_t n = 0;
  for (int i = 0; parts[i] != NULL && n < out_len; i++)
    {
      size_t len = strlen (parts[i]);
      if (n + len + 1 > out_len)
        break;
      memcpy (out_blob + n, parts[i], len + 1);
      n += len + 1;
    }
  return n;
}

/* Run the SILENCE and MERGE output policies and assert the observable result:
 * SILENCE -> child writes produce no piped output; MERGE -> the piped stdout
 * carries both WRITE-OUT and WRITE-ERR while stderr is not piped. */
static int
sps_selftest_run_out_policies (const char *self_path)
{
  int ok = 1;

  /* SILENCE: no pipe for stdout, child output must be discarded. */
  {
    char blob[2048];
    size_t blob_len;
    intptr_t pid;
    sps_stdio_spec_t stdio;
    blob_len = sps_selftest_build_blob (self_path, "--child-write",
                                        blob, sizeof blob);
    memset (&stdio, 0, sizeof stdio);
    stdio.stdin_mode = SPS_STDIO_INHERIT;
    stdio.stdout_mode = SPS_STDIO_SILENCE;
    stdio.stderr_mode = SPS_STDIO_INHERIT;

    pid = sps_spawn (&stdio, blob, blob_len, NULL, NULL, 0);
    if (pid <= 0)
      {
        printf ("FAIL silence spawn\n");
        return 2;
      }
    {
      int exit_code = -1;
      if (sps_selftest_wait (pid, &exit_code) != 0)
        ok = 0;
      printf ("%s silence exit=%d\n", exit_code == 0 ? "PASS" : "FAIL", exit_code);
      if (exit_code != 0)
        ok = 0;
    }
  }

  /* MERGE: only stdout is piped; stderr is directed onto the stdout pipe. */
  {
    char blob[2048];
    size_t blob_len;
    intptr_t pid;
    char buf[256];
    long total = 0;
    int guard = 0;
    sps_fd_t stdout_child_fd, stdout_parent_fd;
    sps_stdio_spec_t stdio;
    blob_len = sps_selftest_build_blob (self_path, "--child-write",
                                        blob, sizeof blob);

    if (sps_pipe (SPS_PIPE_STDOUT, &stdout_parent_fd,
                      &stdout_child_fd) != 0)
      {
        printf ("FAIL merge pipe\n");
        return 2;
      }
    memset (&stdio, 0, sizeof stdio);
    stdio.stdin_mode = SPS_STDIO_INHERIT;
    stdio.stdout_mode = SPS_STDIO_PIPE;
    stdio.stderr_mode = SPS_STDIO_MERGE;
    stdio.stdout_fd = stdout_child_fd;

    pid = sps_spawn (&stdio, blob, blob_len, NULL, NULL, 0);
    if (pid <= 0)
      {
        printf ("FAIL merge spawn\n");
        return 2;
      }
    sps_close (stdout_child_fd);
    {
      int exit_code = -1;
      if (sps_selftest_wait (pid, &exit_code) != 0)
        ok = 0;
    }
    while (guard < 200)
      {
        long n = sps_read (stdout_parent_fd, buf + total,
                           (long) sizeof buf - total);
        if (n == 0)
          break;
        if (n > 0)
          {
            total += n;
            guard = 0;
          }
        else
          {
            guard++;
          }
      }
    sps_close (stdout_parent_fd);
    {
      int has_out = 0, has_err = 0;
      int i;
      for (i = 0; i < (int) total; i++)
        {
          if (i + 10 <= (int) total && memcmp (buf + i, "WRITE-OUT", 9) == 0)
            has_out = 1;
          if (i + 9 <= (int) total && memcmp (buf + i, "WRITE-ERR", 9) == 0)
            has_err = 1;
        }
      ok = ok && has_out && has_err;
      printf ("%s merge has-out=%d has-err=%d total=%ld\n",
              (has_out && has_err) ? "PASS" : "FAIL", has_out, has_err, total);
    }
  }

  return ok ? 0 : 2;
}

int
main (int argc, char **argv)
{
  int result;
  if (argc > 1 && strcmp (argv[1], "--child-echo") == 0)
    return run_child_echo ();
  if (argc > 1 && strcmp (argv[1], "--child-write") == 0)
    return run_child_write ();
  result = sps_selftest_run_parent (argv[0]);
  if (result != 0)
    return result;
  result = sps_selftest_run_error ();
  if (result != 0)
    return result;
  return sps_selftest_run_out_policies (argv[0]);
}
