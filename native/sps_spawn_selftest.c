/*
 * sps_spawn_selftest.c
 *
 * Validates the sps_spawn shim end-to-end without GLib:
 *   - creates the three pipes,
 *   - spawns <this-exe> --child-echo through sps_spawn(),
 *   - writes "hello stdin" to the child's stdin and closes it,
 *   - waits for the child and checks its exit code,
 *   - reads the child's stdout and asserts it echoes the input back.
 *
 * This mirrors the old scratch gprocess_stdin experiment but exercises our
 * own shim instead of GSubprocess.
 */

#include "sps_spawn.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#  include <windows.h>
#else
#  include <fcntl.h>
#  include <sys/wait.h>
#  include <unistd.h>
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

/* Wait for (and reap) the child identified by pid/handle; return its exit code. */
static int
sps_selftest_wait (intptr_t pid, int *out_exit)
{
#if defined(_WIN32)
  DWORD code = 0;
  WaitForSingleObject ((HANDLE) pid, INFINITE);
  GetExitCodeProcess ((HANDLE) pid, &code);
  CloseHandle ((HANDLE) pid);
  *out_exit = (int) code;
  return 0;
#else
  int status;
  if (waitpid ((pid_t) pid, &status, 0) < 0)
    return -1;
  if (WIFEXITED (status))
    *out_exit = WEXITSTATUS (status);
  else
    *out_exit = -1;
  return 0;
#endif
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
  size_t total = 0;
  int exit_code = 0;
  int ok = 1;

#if defined(_WIN32)
  {
    SECURITY_ATTRIBUTES sa;
    HANDLE r, w;
    memset (&sa, 0, sizeof sa);
    sa.nLength = sizeof sa;
    sa.bInheritHandle = FALSE;

    CreatePipe (&r, &w, &sa, 0);                 /* stdin: parent writes, child reads */
    stdin_parent_fd = (sps_fd_t) w;
    stdin_child_fd = (sps_fd_t) r;

    CreatePipe (&r, &w, &sa, 0);                 /* stdout: child writes, parent reads */
    stdout_child_fd = (sps_fd_t) w;
    stdout_parent_fd = (sps_fd_t) r;

    CreatePipe (&r, &w, &sa, 0);                 /* stderr: child writes, parent reads */
    stderr_child_fd = (sps_fd_t) w;
    stderr_parent_fd = (sps_fd_t) r;
  }
#else
  {
    int p[2];
    pipe (p);                                    /* stdin: parent writes p[1], child reads p[0] */
    stdin_parent_fd = (sps_fd_t) p[1];
    stdin_child_fd = (sps_fd_t) p[0];
    pipe (p);                                    /* stdout: child writes p[1], parent reads p[0] */
    stdout_child_fd = (sps_fd_t) p[1];
    stdout_parent_fd = (sps_fd_t) p[0];
    pipe (p);                                    /* stderr */
    stderr_child_fd = (sps_fd_t) p[1];
    stderr_parent_fd = (sps_fd_t) p[0];

    /* Mark every pipe end close-on-exec so posix_spawn drops the copies the
       child does not need for its stdio. adddup2 clears CLOEXEC on the target
       (stdin/stdout/stderr), so exactly the three std fds survive in the child. */
    fcntl ((int) stdin_parent_fd, F_SETFD, FD_CLOEXEC);
    fcntl ((int) stdin_child_fd, F_SETFD, FD_CLOEXEC);
    fcntl ((int) stdout_parent_fd, F_SETFD, FD_CLOEXEC);
    fcntl ((int) stdout_child_fd, F_SETFD, FD_CLOEXEC);
    fcntl ((int) stderr_parent_fd, F_SETFD, FD_CLOEXEC);
    fcntl ((int) stderr_child_fd, F_SETFD, FD_CLOEXEC);
  }
#endif

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

  /* Close the child-facing copies in the parent: stdin_child_fd is the read
     end of the stdin pipe and stdout/stderr_child_fd are the write ends of the
     stdout/stderr pipes. Releasing them lets the parent's read ends hit EOF
     once the child exits. (The caller owns this step, not the shim.) */
#if defined(_WIN32)
  CloseHandle ((HANDLE) stdin_child_fd);
  CloseHandle ((HANDLE) stdout_child_fd);
  CloseHandle ((HANDLE) stderr_child_fd);
#else
  close ((int) stdin_child_fd);
  close ((int) stdout_child_fd);
  close ((int) stderr_child_fd);
#endif

  /* Write payload to the child's stdin, then close it (delivers EOF). */
  {
    size_t written = 0;
    while (written < sizeof payload - 1)
      {
#if defined(_WIN32)
        DWORD n = 0;
        WriteFile ((HANDLE) stdin_parent_fd, payload + written,
                   (DWORD) (sizeof payload - 1 - written), &n, NULL);
        written += n;
#else
        ssize_t n = write ((int) stdin_parent_fd, payload + written,
                           sizeof payload - 1 - written);
        written += (size_t) n;
#endif
      }
  }
#if defined(_WIN32)
  CloseHandle ((HANDLE) stdin_parent_fd);
#else
  close ((int) stdin_parent_fd);
#endif

  if (sps_selftest_wait (pid, &exit_code) != 0)
    ok = 0;

  /* Read the child's stdout until EOF. */
  for (;;)
    {
#if defined(_WIN32)
      DWORD n = 0;
      if (!ReadFile ((HANDLE) stdout_parent_fd, buf + total,
                     (DWORD) (sizeof buf - total), &n, NULL) || n == 0)
        break;
      total += n;
#else
      ssize_t n = read ((int) stdout_parent_fd, buf + total, sizeof buf - total);
      if (n <= 0)
        break;
      total += (size_t) n;
#endif
      if (total >= sizeof buf)
        break;
    }

  ok = ok && exit_code == 0;
  ok = ok && total == sizeof payload - 1
          && memcmp (buf, payload, sizeof payload - 1) == 0;

  printf ("%s exit=%d echoed=\"%.*s\"\n", ok ? "PASS" : "FAIL",
          exit_code, (int) total, buf);

#if defined(_WIN32)
  CloseHandle ((HANDLE) stdout_parent_fd);
  CloseHandle ((HANDLE) stderr_parent_fd);
#else
  close ((int) stdout_parent_fd);
  close ((int) stderr_parent_fd);
#endif

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
