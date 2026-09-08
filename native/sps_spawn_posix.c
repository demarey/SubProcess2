/*
 * sps_spawn_posix.c
 *
 * macOS/Linux implementation of sps_spawn() using posix_spawn().
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
#include <spawn.h>
#include <stdio.h>
#include <string.h>
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

intptr_t
sps_spawn (sps_fd_t child_stdin, sps_fd_t child_stdout, sps_fd_t child_stderr,
           const char *args, size_t args_len, const char *cwd,
           char *errbuf, size_t errbuf_len)
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

  err = posix_spawn_file_actions_adddup2 (&actions, (int) child_stdin, STDIN_FILENO);
  if (err != 0)
    goto fail_actions;
  err = posix_spawn_file_actions_adddup2 (&actions, (int) child_stdout, STDOUT_FILENO);
  if (err != 0)
    goto fail_actions;
  err = posix_spawn_file_actions_adddup2 (&actions, (int) child_stderr, STDERR_FILENO);
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
