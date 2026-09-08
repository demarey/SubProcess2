/*
 * sps_spawn_win.c
 *
 * Windows implementation of the sps_* process helper using CreateProcessW()
 * for launch and CreatePipe / ReadFile / WriteFile / CloseHandle for I/O and
 * OpenProcess + WaitForSingleObject / GetExitCodeProcess / TerminateProcess
 * for lifecycle.
 *
 * On Windows sps_fd_t is a HANDLE. The pipe ends returned by sps_pipe (and
 * given to sps_spawn) are HANDLEs; the child-facing ends are made inheritable
 * and the parent-facing ends are not, so the child only receives the three
 * descriptors it needs for its stdio.
 */

#include "sps_spawn.h"
#include "sps_spawn_args.h"

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Registry of live child processes keyed by OS pid.
 *
 * The handle returned by CreateProcess is kept open for the lifetime of the
 * child instead of being closed after spawn, because once a Windows process
 * exits and its last handle is closed the process object is destroyed and it
 * can no longer be re-opened by pid. sps_wait and sps_kill must therefore use
 * the retained handle (via this registry) rather than OpenProcess. */
#define SPS_MAX_PROC 1024
typedef struct
{
  intptr_t pid;
  HANDLE handle;
} sps_proc_entry;

static sps_proc_entry sps_procs[SPS_MAX_PROC];
static DWORD sps_proc_count;

static sps_proc_entry *
sps_proc_find (intptr_t pid)
{
  DWORD i;
  for (i = 0; i < sps_proc_count; i++)
    if (sps_procs[i].pid == pid)
      return &sps_procs[i];
  return NULL;
}

static int
sps_proc_register (intptr_t pid, HANDLE handle)
{
  if (sps_proc_find (pid) != NULL)
    {
      CloseHandle (handle);
      return 0;
    }
  if (sps_proc_count < SPS_MAX_PROC)
    {
      sps_procs[sps_proc_count].pid = pid;
      sps_procs[sps_proc_count].handle = handle;
      sps_proc_count++;
      return 0;
    }
  CloseHandle (handle);
  return -1;
}

static void
sps_proc_remove (intptr_t pid)
{
  DWORD i;
  for (i = 0; i < sps_proc_count; i++)
    if (sps_procs[i].pid == pid)
      {
        sps_procs[i] = sps_procs[sps_proc_count - 1];
        sps_proc_count--;
        return;
      }
}

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

int
sps_pipe (int kind, sps_fd_t *out_parent, sps_fd_t *out_child)
{
  HANDLE hRead, hWrite;
  SECURITY_ATTRIBUTES sa;
  HANDLE child_end, parent_end;

  memset (&sa, 0, sizeof sa);
  sa.nLength = sizeof sa;
  sa.bInheritHandle = TRUE;                  /* let the child end be inherited */
  sa.lpSecurityDescriptor = NULL;

  if (!CreatePipe (&hRead, &hWrite, &sa, 0))
    return -1;

  if (kind == SPS_PIPE_STDIN)
    {
      child_end = hRead;                     /* child reads */
      parent_end = hWrite;                   /* parent writes */
    }
  else
    {
      child_end = hWrite;                    /* child writes */
      parent_end = hRead;                    /* parent reads */
    }

  /* The child-facing end is inherited (redundant given the security
     attributes above, kept for clarity); the parent end must not be, so the
     child does not keep the parent's ends open (which would hold the pipe
     open past EOF). */
  SetHandleInformation (child_end, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
  SetHandleInformation (parent_end, HANDLE_FLAG_INHERIT, 0);

  *out_child = (sps_fd_t) child_end;
  *out_parent = (sps_fd_t) parent_end;
  return 0;
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
    {
      /* Keep the error wording close to POSIX so platform-agnostic callers
         that grep for "No such file or directory" behave the same on Windows
         as on Unix (see SyncSubProcessTest>>testRunningANonExistingCommand). */
      DWORD win_err = GetLastError ();
      if (win_err == ERROR_FILE_NOT_FOUND || win_err == ERROR_PATH_NOT_FOUND)
        return sps_fill_errbuf (errbuf, errbuf_len,
                                "sps_spawn: No such file or directory", 0);
      return sps_fill_errbuf (errbuf, errbuf_len, "sps_spawn: CreateProcessW failed",
                              win_err);
    }

  /* Return the real OS process id so the rest of the package can treat the
     result uniformly with Unix (wait/terminate by pid). Keep the process
     handle open in the registry: the child may exit before a later wait, at
     which point it could no longer be re-opened by pid. Only the thread
     handle is closed here. GetProcessId is only supported on Vista+, matching
     _WIN32_WINNT=0x0601. */
  {
    DWORD os_pid = GetProcessId (proc_info.hProcess);
    CloseHandle (proc_info.hThread);
    if (os_pid == 0)
      {
        CloseHandle (proc_info.hProcess);
        return sps_fill_errbuf (errbuf, errbuf_len, "sps_spawn: GetProcessId failed",
                                GetLastError ());
      }
    if (sps_proc_register ((intptr_t) os_pid, proc_info.hProcess) != 0)
      return sps_fill_errbuf (errbuf, errbuf_len,
                              "sps_spawn: process registry full", 0);
    return (intptr_t) os_pid;
  }
}

int
sps_fd_set_nonblocking (sps_fd_t fd)
{
  /* Windows anonymous pipe reads are made non-blocking inside sps_read via
     PeekNamedPipe; this helper is a no-op kept for interface parity. */
  (void) fd;
  return 0;
}

long
sps_read (sps_fd_t fd, char *buf, size_t len)
{
  HANDLE h = (HANDLE) fd;
  DWORD available = 0, total = 0, pending = 0;

  /* PeekNamedPipe tells us whether data is ready without blocking, which is
     how we emulate a non-blocking read. lpTotalBytesAvail can exceed
     lpBytesAvail right after a writer closes (bytes pending in the pipe's
     write buffer), so we must read whenever total > 0 rather than only when
     available > 0; otherwise a just-exited child's final output is never
     drained. */
  if (!PeekNamedPipe (h, NULL, 0, &available, &total, &pending))
    {
      if (GetLastError () == ERROR_BROKEN_PIPE)
        return 0;                            /* EOF: all write ends closed */
      return -1;
    }

  if (available == 0 && total == 0)
    return -1;                               /* would block: no data at all */

  {
    DWORD nread = 0;
    if (!ReadFile (h, buf, (DWORD) len, &nread, NULL))
      {
        if (GetLastError () == ERROR_BROKEN_PIPE)
          return 0;                          /* EOF after draining */
        return -1;
      }
    return (long) nread;
  }
}

long
sps_write (sps_fd_t fd, const char *buf, size_t len)
{
  DWORD nwritten = 0;
  if (!WriteFile ((HANDLE) fd, buf, (DWORD) len, &nwritten, NULL))
    return -1;
  return (long) nwritten;
}

int
sps_close (sps_fd_t fd)
{
  return CloseHandle ((HANDLE) fd) ? 0 : -1;
}

int
sps_wait (intptr_t pid, int block, int *out_status)
{
  sps_proc_entry *entry = sps_proc_find (pid);
  if (entry == NULL)
    return -1;

  if (WaitForSingleObject (entry->handle, block ? INFINITE : 0) == WAIT_TIMEOUT)
    return 0;                              /* still running (poll mode) */

  {
    DWORD code = 0;
    GetExitCodeProcess (entry->handle, &code);

    /* Close the handle and drop the registry entry once the exit has been
       reported; a later sps_wait for the same pid then fails, which callers
       treat as "already reaped/absent". */
    sps_proc_remove (pid);
    CloseHandle (entry->handle);

    if (code == STILL_ACTIVE)
      return 0;                            /* not actually exited (edge case) */

    /* Encode the exit code into a POSIX-like wait status so the caller's
       WIFEXITED/WEXITSTATUS decoding reports it directly. */
    *out_status = ((int) code << 8) & 0xFFFFFF00;
    return 1;
  }
}

int
sps_kill (intptr_t pid)
{
  sps_proc_entry *entry = sps_proc_find (pid);
  if (entry == NULL)
    return -1;
  /* Leave the handle registered so a subsequent sps_wait can reap the exit. */
  if (!TerminateProcess (entry->handle, 1))
    return -1;
  return 0;
}
