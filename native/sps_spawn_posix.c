/*
 * sps_spawn_posix.c
 *
 * macOS/Linux implementation of the sps_* process helper using posix_spawn()
 * for launch and plain pipe(2)/read(2)/write(2)/waitpid(2)/kill(2) for I/O
 * and lifecycle.
 *
 * The working directory is honoured through the platform-specific spawn
 * attribute/file-action extensions:
 *   - macOS   : posix_spawnattr_setworkingdir_np()
 *   - glibc   : posix_spawn_file_actions_addchdir_np()  (glibc >= 2.29)
 * When neither is available and a cwd is requested, spawn fails with a clear
 * error message rather than silently launching from the wrong directory.
 */

#ifndef _GNU_SOURCE
#  define _GNU_SOURCE     /* for posix_spawn_file_actions_addchdir_np (glibc) */
#endif

#include "sps_spawn.h"
#include "sps_spawn_args.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#if defined(__APPLE__)
#  include <crt_externs.h>
#  define SPS_ENVIRON (*_NSGetEnviron ())
#else
extern char **environ;
#  define SPS_ENVIRON environ
#endif

/*
 * Set the child working directory through posix_spawn_file_actions_addchdir_np,
 * which both macOS (via the `_np` libSystem extension) and glibc (>= 2.29)
 * provide. This avoids the fork()+chdir()+exec() fallback needed on older
 * systems.
 */
static void
sps_apply_cwd (posix_spawn_file_actions_t *actions, const char *cwd)
{
  if (cwd != NULL)
    posix_spawn_file_actions_addchdir_np (actions, cwd);
}

static int
sps_fill_errbuf (char *errbuf, size_t errbuf_len, const char *msg, int errnum)
{
  if (errbuf == NULL || errbuf_len == 0)
    return -1;

  if (errnum != 0)
    snprintf (errbuf, errbuf_len, "%s: %s", msg, strerror (errnum));
  else
    snprintf (errbuf, errbuf_len, "%s", msg);

  return -1;
}

int
sps_pipe (int kind, sps_fd_t *out_parent, sps_fd_t *out_child)
{
  int fds[2];
  int parent_idx, child_idx;

  if (pipe (fds) != 0)
    return -1;

  if (kind == SPS_PIPE_STDIN)
    {
      /* child reads fds[0], parent writes fds[1] */
      parent_idx = 1;
      child_idx = 0;
    }
  else
    {
      /* child writes fds[1], parent reads fds[0] */
      parent_idx = 0;
      child_idx = 1;
    }

  /* Prevent the child from inheriting the parent's ends: keep every end
     close-on-exec; posix_spawn's adddup2 onto 0/1/2 clears CLOEXEC on exactly
     the three descriptors the child uses for its stdio. */
  fcntl (fds[0], F_SETFD, FD_CLOEXEC);
  fcntl (fds[1], F_SETFD, FD_CLOEXEC);

  *out_parent = (sps_fd_t) fds[parent_idx];
  *out_child = (sps_fd_t) fds[child_idx];
  return 0;
}

/*
 * Apply the file action that wires one of the child's standard streams
 * (fd is STDIN_FILENO, STDOUT_FILENO or STDERR_FILENO) according to mode.
 * Returns 0 on success, -1 on failure. */
static int
sps_apply_stdio (posix_spawn_file_actions_t *actions, int fd,
                 sps_stdio_mode_t mode, sps_fd_t pipe_fd,
                 int merge /* stderr merge targets resolved stdin/stdout */)
{
  switch (mode)
    {
    case SPS_STDIO_INHERIT:
      return 0;                              /* keep the caller's fd */
    case SPS_STDIO_SILENCE:
      return posix_spawn_file_actions_addopen (actions, fd, "/dev/null",
                                               O_RDWR, 0);
    case SPS_STDIO_MERGE:
      return posix_spawn_file_actions_adddup2 (actions, merge, fd);
    case SPS_STDIO_PIPE:
    default:
      return posix_spawn_file_actions_adddup2 (actions, (int) pipe_fd, fd);
    }
}

intptr_t
sps_spawn (const sps_stdio_spec_t *stdio, const char *args, size_t args_len,
           const char *cwd, char *errbuf, size_t errbuf_len)
{
  posix_spawn_file_actions_t actions;
  char **argv = NULL;
  pid_t pid;
  int err;

  if (sps_split_args (args, args_len, &argv) != 0)
    return sps_fill_errbuf (errbuf, errbuf_len, "sps_spawn: empty argument blob", 0);

  err = posix_spawn_file_actions_init (&actions);
  if (err != 0)
    {
      sps_free_args (argv);
      return sps_fill_errbuf (errbuf, errbuf_len, "sps_spawn: file_actions_init failed", err);
    }

  /* Process in stdin, stdout, stderr order so that a MERGE stderr can target
     whatever stdout (or stdin) was already resolved. */
  err = sps_apply_stdio (&actions, STDIN_FILENO, stdio->stdin_mode,
                         stdio->stdin_fd, 0);
  if (err != 0)
    goto fail_actions;
  err = sps_apply_stdio (&actions, STDOUT_FILENO, stdio->stdout_mode,
                         stdio->stdout_fd, STDOUT_FILENO);
  if (err != 0)
    goto fail_actions;
  err = sps_apply_stdio (&actions, STDERR_FILENO, stdio->stderr_mode,
                         stdio->stderr_fd, STDOUT_FILENO);
  if (err != 0)
    goto fail_actions;

  sps_apply_cwd (&actions, cwd);

  /* No spawn attributes: the environment is inherited unchanged (SPS_ENVIRON)
     and no signal/scheduling attributes are modified. */
  err = posix_spawn (&pid, argv[0], &actions,
                     NULL, (char *const *) argv, SPS_ENVIRON);
  if (err != 0)
    sps_fill_errbuf (errbuf, errbuf_len, "sps_spawn: posix_spawn failed", err);

  posix_spawn_file_actions_destroy (&actions);
  sps_free_args (argv);

  if (err != 0)
    return -1;
  return (intptr_t) pid;

fail_actions:
  posix_spawn_file_actions_destroy (&actions);
  sps_free_args (argv);
  return -1;
}

int
sps_fd_set_nonblocking (sps_fd_t fd)
{
  int flags = fcntl ((int) fd, F_GETFL, 0);
  if (flags == -1)
    return -1;
  return fcntl ((int) fd, F_SETFL, flags | O_NONBLOCK);
}

long
sps_read (sps_fd_t fd, char *buf, size_t len)
{
  ssize_t n = read ((int) fd, buf, len);
  return (long) n;
}

long
sps_write (sps_fd_t fd, const char *buf, size_t len)
{
  ssize_t n = write ((int) fd, buf, len);
  return (long) n;
}

int
sps_close (sps_fd_t fd)
{
  return close ((int) fd) == 0 ? 0 : -1;
}

int
sps_wait (intptr_t pid, int block, int *out_status)
{
  int status = 0;
  pid_t r = waitpid ((pid_t) pid, &status, block ? 0 : WNOHANG);
  if (r == 0)
    return 0;                              /* still running (poll mode) */
  if (r < 0)
    return -1;                             /* ECHILD or other error */
  *out_status = status;                    /* reaped: raw wait status */
  return 1;
}

int
sps_kill (intptr_t pid)
{
  return kill ((pid_t) pid, SIGKILL) == 0 ? 0 : -1;
}
