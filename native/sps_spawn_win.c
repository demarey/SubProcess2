/*
 * sps_spawn_win.c
 *
 * Windows implementation of sps_spawn() using CreateProcessW().
 *
 * On Windows sps_fd_t is a HANDLE (the child-facing pipe end):
 *   - child_stdin  : the read handle that becomes the child's stdin,
 *   - child_stdout : the write handle that becomes the child's stdout,
 *   - child_stderr : the write handle that becomes the child's stderr.
 *
 * These handles are made inheritable (SetHandleInformation) and wired into the
 * child via STARTUPINFO (STARTF_USESTDHANDLES). The returned "pid" is the
 * process HANDLE, which the caller later uses with WaitForSingleObject /
 * GetExitCodeProcess / TerminateProcess.
 */

#include "sps_spawn.h"
#include "sps_spawn_args.h"

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int
sps_fill_errbuf (char *errbuf, size_t errbuf_len, const char *msg, DWORD errnum)
{
  if (errbuf == NULL || errbuf_len == 0)
    return -1;

  if (errnum == 0)
    snprintf (errbuf, errbuf_len, "%s", msg);
  else
    {
      char *sysmsg = NULL;
      FormatMessageA (FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM
                      | FORMAT_MESSAGE_IGNORE_INSERTS,
                      NULL, errnum, 0, (char *) &sysmsg, 0, NULL);
      snprintf (errbuf, errbuf_len, "%s: %s", msg,
                sysmsg ? sysmsg : "unknown error");
      if (sysmsg)
        LocalFree (sysmsg);
    }

  return -1;
}

/* Build a Windows command line from a NULL-terminated narrow argv, quoting
   arguments that contain spaces and escaping embedded quotes, then convert
   the whole thing to UTF-16. The caller must LocalFree() the result. */
static wchar_t *
sps_build_command_line (char *const *argv, size_t *out_len)
{
  size_t total = 0, i;
  char *narrow;
  wchar_t *wide;
  int wide_len;

  for (i = 0; argv[i] != NULL; i++)
    {
      size_t len = strlen (argv[i]);
      size_t arglen = 0;
      size_t j;
      int needs_quote = 0;

      for (j = 0; j < len; j++)
        if (argv[i][j] == ' ' || argv[i][j] == '\t' || argv[i][j] == '"')
          {
            needs_quote = 1;
            break;
          }

      if (needs_quote)
        {
          arglen = 2;                          /* surrounding quotes */
          for (j = 0; j < len; j++)
            {
              if (argv[i][j] == '"')
                arglen += 2;                   /* \" escaped */
              else
                arglen += 1;
            }
        }
      else
        arglen = len;

      if (i > 0)
        total += 1;                            /* leading space */
      total += arglen;
    }
  total += 1;                                  /* NUL */

  narrow = (char *) malloc (total);
  if (narrow == NULL)
    return NULL;

  {
    size_t p = 0;
    for (i = 0; argv[i] != NULL; i++)
      {
        size_t len = strlen (argv[i]);
        size_t j;
        int needs_quote = 0;

        for (j = 0; j < len; j++)
          if (argv[i][j] == ' ' || argv[i][j] == '\t' || argv[i][j] == '"')
            {
              needs_quote = 1;
              break;
            }

        if (i > 0)
          narrow[p++] = ' ';

        if (needs_quote)
          narrow[p++] = '"';
        for (j = 0; j < len; j++)
          {
            if (argv[i][j] == '"')
              narrow[p++] = '\\';
            narrow[p++] = argv[i][j];
          }
        if (needs_quote)
          narrow[p++] = '"';
      }
    narrow[p] = '\0';
  }

  wide_len = MultiByteToWideChar (CP_UTF8, 0, narrow, -1, NULL, 0);
  wide = (wchar_t *) LocalAlloc (LMEM_FIXED, (size_t) wide_len * sizeof (wchar_t));
  if (wide != NULL)
    MultiByteToWideChar (CP_UTF8, 0, narrow, -1, wide, wide_len);

  free (narrow);
  *out_len = (size_t) wide_len;
  return wide;
}

intptr_t
sps_spawn (sps_fd_t child_stdin, sps_fd_t child_stdout, sps_fd_t child_stderr,
           const char *args, size_t args_len, const char *cwd,
           char *errbuf, size_t errbuf_len)
{
  HANDLE stdin_handle = (HANDLE) child_stdin;
  HANDLE stdout_handle = (HANDLE) child_stdout;
  HANDLE stderr_handle = (HANDLE) child_stderr;
  PROCESS_INFORMATION proc_info;
  STARTUPINFOW startup_info;
  wchar_t *command_line = NULL;
  wchar_t *wide_cwd = NULL;
  size_t cmd_len = 0;
  char **argv = NULL;
  BOOL ok;

  if (sps_split_args (args, args_len, &argv) != 0)
    return sps_fill_errbuf (errbuf, errbuf_len, "sps_spawn: empty argument blob", 0);

  /* The child side of each pipe must be inheritable. */
  SetHandleInformation (stdin_handle, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
  SetHandleInformation (stdout_handle, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
  SetHandleInformation (stderr_handle, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);

  memset (&proc_info, 0, sizeof proc_info);
  memset (&startup_info, 0, sizeof startup_info);
  startup_info.cb = sizeof startup_info;
  startup_info.dwFlags = STARTF_USESTDHANDLES;
  startup_info.hStdInput = stdin_handle;
  startup_info.hStdOutput = stdout_handle;
  startup_info.hStdError = stderr_handle;

  command_line = sps_build_command_line (argv, &cmd_len);
  sps_free_args (argv);
  if (command_line == NULL)
    return sps_fill_errbuf (errbuf, errbuf_len, "sps_spawn: cannot build command line", 0);

  if (cwd != NULL)
    {
      int wide_cwd_len = MultiByteToWideChar (CP_UTF8, 0, cwd, -1, NULL, 0);
      wide_cwd = (wchar_t *) LocalAlloc (LMEM_FIXED,
                                         (size_t) wide_cwd_len * sizeof (wchar_t));
      if (wide_cwd == NULL)
        {
          LocalFree (command_line);
          return sps_fill_errbuf (errbuf, errbuf_len, "sps_spawn: cannot convert cwd", 0);
        }
      MultiByteToWideChar (CP_UTF8, 0, cwd, -1, wide_cwd, wide_cwd_len);
    }

  ok = CreateProcessW (NULL, command_line, NULL, NULL, TRUE,
                       CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW,
                       NULL, wide_cwd, &startup_info, &proc_info);

  if (wide_cwd)
    LocalFree (wide_cwd);
  LocalFree (command_line);

  if (!ok)
    return sps_fill_errbuf (errbuf, errbuf_len, "sps_spawn: CreateProcessW failed",
                            GetLastError ());

  /* Return the real OS process id so the rest of the package can treat the
     result uniformly with Unix (wait/terminate by re-opening the process via
     OpenProcess). Close both handles; the thread handle is not needed.
     GetProcessId is only supported on Vista+, matching _WIN32_WINNT=0x0601. */
  {
    DWORD os_pid = GetProcessId (proc_info.hProcess);
    CloseHandle (proc_info.hThread);
    CloseHandle (proc_info.hProcess);
    if (os_pid == 0)
      return sps_fill_errbuf (errbuf, errbuf_len, "sps_spawn: GetProcessId failed",
                              GetLastError ());
    return (intptr_t) os_pid;
  }
}

int
sps_fd_set_nonblocking (sps_fd_t fd)
{
  /* Windows anonymous pipe reads are made non-blocking via PeekNamedPipe by
     the caller; this helper is a no-op kept for interface parity. */
  (void) fd;
  return 0;
}
