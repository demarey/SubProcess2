/*
 * sps_spawn_win.c
 *
 * Windows implementation of the sps_* process helper using CreateProcessW()
 * for launch and CreatePipe / ReadFile / WriteFile / CloseHandle for I/O and
 * WaitForSingleObject / GetExitCodeProcess / TerminateProcess for lifecycle.
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

/* The process descriptor returned by sps_spawn is an opaque token passed back
 * to sps_wait / sps_kill. On Unix the token is the OS pid; on Windows it is
 * the HANDLE returned by CreateProcess. On Windows the handle is kept open for
 * the lifetime of the child (the token), because once a process exits and its
 * last handle is closed the process object is destroyed and it can no longer
 * be opened by pid. sps_wait reaps and closes the handle when it reports the
 * exit; sps_kill terminates but deliberately leaves the handle open so the
 * subsequent sps_wait can still reap. There is therefore no long-lived
 * registry of child processes in the shim.
 *
 * On Windows the exit code is encoded into a POSIX-like wait status so the
 * shared POSIX WIFEXITED/WEXITSTATUS decoding works unmodified. */

/* Low-level helpers, defined at the bottom of this file. */
static char *sps_system_message (DWORD errnum);
static int sps_fill_errbuf (char *errbuf, size_t errbuf_len,
                            const char *msg, DWORD errnum);
static wchar_t *sps_utf8_to_wide (const char *narrow, size_t *out_length);
static wchar_t *sps_build_command_line (char *const *argv, size_t *out_length);
typedef struct
{
  HANDLE in;
  HANDLE out;
  HANDLE err;
} sps_stdio_handles_t;
static void sps_resolve_stdio_handles (const sps_stdio_spec_t *stdio,
                                       sps_stdio_handles_t *handles);
static void sps_set_stdio_inheritable (const sps_stdio_handles_t *handles);
static void sps_close_silence_handles (const sps_stdio_spec_t *stdio,
                                       const sps_stdio_handles_t *handles);

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
sps_spawn (const sps_stdio_spec_t *stdio, const char *args, size_t args_len,
           const char *cwd, char *errbuf, size_t errbuf_len)
{
  sps_stdio_handles_t handles;
  PROCESS_INFORMATION proc_info;
  STARTUPINFOW startup_info;
  wchar_t *command_line = NULL;
  wchar_t *wide_cwd = NULL;
  char **argv = NULL;
  BOOL ok;

  if (sps_split_args (args, args_len, &argv) != 0)
    return sps_fill_errbuf (errbuf, errbuf_len, "sps_spawn: empty argument blob", 0);

  command_line = sps_build_command_line (argv, NULL);
  sps_free_args (argv);
  if (command_line == NULL)
    return sps_fill_errbuf (errbuf, errbuf_len, "sps_spawn: cannot build command line", 0);

  if (cwd != NULL)
    {
      wide_cwd = sps_utf8_to_wide (cwd, NULL);
      if (wide_cwd == NULL)
        {
          LocalFree (command_line);
          return sps_fill_errbuf (errbuf, errbuf_len, "sps_spawn: cannot convert cwd", 0);
        }
    }

  sps_resolve_stdio_handles (stdio, &handles);
  sps_set_stdio_inheritable (&handles);

  memset (&proc_info, 0, sizeof proc_info);
  memset (&startup_info, 0, sizeof startup_info);
  startup_info.cb = sizeof startup_info;
  startup_info.dwFlags = STARTF_USESTDHANDLES;
  startup_info.hStdInput  = handles.in;
  startup_info.hStdOutput = handles.out;
  startup_info.hStdError  = handles.err;

  ok = CreateProcessW (NULL, command_line, NULL, NULL, TRUE,
                       CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW,
                       NULL, wide_cwd, &startup_info, &proc_info);

  /* NUL handles we opened ourselves for SILENCE close on both outcomes;
     pipe ends remain owned by the caller (closed via sps_close after spawn). */
  sps_close_silence_handles (stdio, &handles);
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
      return sps_fill_errbuf (errbuf, errbuf_len,
                              "sps_spawn: CreateProcessW failed", win_err);
    }

  /* Return the process HANDLE itself as the opaque token. The rest of the
     package treats it uniformly with the Unix pid (wait/terminate by token).
     Keep the handle open as the token: the child may exit before a later wait,
     at which point it could no longer be re-opened by pid. sps_wait reaps and
     closes it. Only the thread handle is closed here. */
  CloseHandle (proc_info.hThread);
  return (intptr_t) proc_info.hProcess;
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
  DWORD available = 0, total = 0, pending = 0, bytes_read = 0;

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

  if (!ReadFile (h, buf, (DWORD) len, &bytes_read, NULL))
    {
      if (GetLastError () == ERROR_BROKEN_PIPE)
        return 0;                            /* EOF after draining */
      return -1;
    }
  return (long) bytes_read;
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
sps_wait (intptr_t token, int block, int *out_status)
{
  HANDLE h = (HANDLE) token;
  DWORD res, code = 0;

  res = WaitForSingleObject (h, block ? INFINITE : 0);

  if (res == WAIT_TIMEOUT)
    return 0;                              /* still running (poll mode) */

  if (res != WAIT_OBJECT_0)
    return -1;                             /* WAIT_FAILED/ABANDONED: bad/reaped handle */

  GetExitCodeProcess (h, &code);

  /* Reap: the handle opened by sps_spawn is closed here (and only here), once
     the exit has been reported. A later sps_wait on the same token sees an
     invalid handle and answers -1, which callers treat as already reaped. */
  CloseHandle (h);

  if (code == STILL_ACTIVE)
    return 0;                            /* not actually exited (edge case) */

  /* Encode the exit code into a POSIX-like wait status so the caller's
     WIFEXITED/WEXITSTATUS decoding reports it directly. */
  *out_status = ((int) code << 8) & 0xFFFFFF00;
  return 1;
}

int
sps_kill (intptr_t token)
{
  HANDLE h = (HANDLE) token;
  if (!TerminateProcess (h, 1))
    return -1;
  /* Leave the handle open as the token so a subsequent sps_wait can reap. */
  return 0;
}

/* --------------------------------------------------------------------------
 * Low-level helpers
 * ------------------------------------------------------------------------ */

/* Retrieve the localized system description for a Windows error number as a
   UTF-8 string. The caller frees the result with LocalFree, or NULL when no
   description is available. */
static char *
sps_system_message (DWORD errnum)
{
  wchar_t *wide_message = NULL;
  char *message = NULL;
  DWORD wide_length;
  int size;

  wide_length = FormatMessageW (
    FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM
      | FORMAT_MESSAGE_IGNORE_INSERTS,
    NULL, errnum, 0, (wchar_t *) &wide_message, 0, NULL);
  if (wide_message == NULL)
    return NULL;

  size = WideCharToMultiByte (CP_UTF8, 0, wide_message, (int) wide_length,
                              NULL, 0, NULL, NULL);
  if (size > 0)
    {
      message = (char *) LocalAlloc (LMEM_FIXED, (size_t) size + 1);
      if (message != NULL)
        {
          WideCharToMultiByte (CP_UTF8, 0, wide_message, (int) wide_length,
                               message, size, NULL, NULL);
          message[size] = '\0';
        }
    }
  LocalFree (wide_message);
  return message;
}

static int
sps_fill_errbuf (char *errbuf, size_t errbuf_len, const char *msg, DWORD errnum)
{
  char *owned_message = NULL;
  const char *detail = NULL;

  if (errbuf == NULL || errbuf_len == 0)
    return -1;

  if (errnum != 0)
    {
      owned_message = sps_system_message (errnum);
      detail = owned_message != NULL ? owned_message : "unknown error";
    }

  if (detail != NULL)
    snprintf (errbuf, errbuf_len, "%s: %s", msg, detail);
  else
    snprintf (errbuf, errbuf_len, "%s", msg);

  if (owned_message != NULL)
    LocalFree (owned_message);

  return -1;
}

/* Answer whether an argument must be quoted in a command line because it
   contains a space, tab, or an embedded double quote. */
static int
sps_argument_needs_quoting (const char *argument)
{
  for (; *argument != '\0'; argument++)
    if (*argument == ' ' || *argument == '\t' || *argument == '"')
      return 1;
  return 0;
}

/* Length of an argument once it is written quoted/escaped into a command
   line (see sps_write_argument). */
static size_t
sps_quoted_argument_length (const char *argument)
{
  size_t length = strlen (argument);
  size_t extra = 0;
  const char *cursor;

  if (!sps_argument_needs_quoting (argument))
    return length;

  extra += 2;                                /* surrounding quotes */
  for (cursor = argument; *cursor != '\0'; cursor++)
    if (*cursor == '"')
      extra += 1;                            /* added backslash */

  return length + extra;
}

/* Write an argument (quoted and with embedded quotes escaped) into output,
   answering how many bytes were written. */
static size_t
sps_write_argument (const char *argument, char *output)
{
  size_t position = 0;
  const char *cursor;

  if (sps_argument_needs_quoting (argument))
    output[position++] = '"';
  for (cursor = argument; *cursor != '\0'; cursor++)
    {
      if (*cursor == '"')
        output[position++] = '\\';
      output[position++] = *cursor;
    }
  if (sps_argument_needs_quoting (argument))
    output[position++] = '"';

  return position;
}

/* Write the arguments of argv into output as a NUL-terminated command line,
   separated by single spaces, sized beforehand by sps_build_command_line. */
static void
sps_fill_command_line (char *output, char *const *argv, size_t argument_count)
{
  size_t position = 0;
  size_t index;

  for (index = 0; index < argument_count; index++)
    {
      if (index > 0)
        output[position++] = ' ';
      position += sps_write_argument (argv[index], output + position);
    }
  output[position] = '\0';
}

/* Convert a NUL-terminated UTF-8 string to a UTF-16 string. The caller frees
   the result with LocalFree. */
static wchar_t *
sps_utf8_to_wide (const char *narrow, size_t *out_length)
{
  wchar_t *wide;
  int wide_length;

  wide_length = MultiByteToWideChar (CP_UTF8, 0, narrow, -1, NULL, 0);
  wide = (wchar_t *) LocalAlloc (LMEM_FIXED,
                                 (size_t) wide_length * sizeof (wchar_t));
  if (wide != NULL)
    MultiByteToWideChar (CP_UTF8, 0, narrow, -1, wide, wide_length);

  if (out_length != NULL)
    *out_length = (size_t) wide_length;
  return wide;
}

/* Build a Windows command line from a NULL-terminated narrow argv, quoting
   arguments that contain spaces and escaping embedded quotes, then convert
   the whole thing to UTF-16. The caller must LocalFree() the result. */
static wchar_t *
sps_build_command_line (char *const *argv, size_t *out_length)
{
  size_t total_length = 0;
  size_t argument_count = 0;
  size_t index;
  char *narrow_command_line;
  wchar_t *wide_command_line;

  for (index = 0; argv[index] != NULL; index++)
    {
      total_length += sps_quoted_argument_length (argv[index]);
      if (index > 0)
        total_length += 1;                   /* separating space */
      argument_count++;
    }
  total_length += 1;                         /* NUL */

  narrow_command_line = (char *) malloc (total_length);
  if (narrow_command_line == NULL)
    return NULL;

  sps_fill_command_line (narrow_command_line, argv, argument_count);
  wide_command_line = sps_utf8_to_wide (narrow_command_line, out_length);

  free (narrow_command_line);
  return wide_command_line;
}

/* Resolve a HANDLE for a stream wired with SILENCE / PIPE / MERGE: SILENCE
 * opens NUL, MERGE reuses the already-resolved stdout handle, PIPE uses the
 * given pipe end, INHERIT uses the caller's real standard handle so the child
 * sees the parent's descriptor even under STARTF_USESTDHANDLES. */
static HANDLE
sps_resolve_stdio (sps_stdio_mode_t mode, sps_fd_t pipe_fd,
                   DWORD std_kind, HANDLE merged_stdout)
{
  switch (mode)
    {
    case SPS_STDIO_INHERIT:
      return GetStdHandle (std_kind);
    case SPS_STDIO_SILENCE:
      return CreateFileW (L"NUL", GENERIC_READ | GENERIC_WRITE,
                          FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING,
                          FILE_ATTRIBUTE_NORMAL, NULL);
    case SPS_STDIO_MERGE:
      return merged_stdout;
    case SPS_STDIO_PIPE:
    default:
      return (HANDLE) pipe_fd;
    }
}

static void
sps_resolve_stdio_handles (const sps_stdio_spec_t *stdio,
                           sps_stdio_handles_t *handles)
{
  handles->in  = sps_resolve_stdio (stdio->stdin_mode,  stdio->stdin_fd,
                                    STD_INPUT_HANDLE,  NULL);
  handles->out = sps_resolve_stdio (stdio->stdout_mode, stdio->stdout_fd,
                                    STD_OUTPUT_HANDLE, NULL);
  handles->err = sps_resolve_stdio (stdio->stderr_mode, stdio->stderr_fd,
                                    STD_ERROR_HANDLE,  handles->out);
}

static void
sps_set_stdio_inheritable (const sps_stdio_handles_t *handles)
{
  SetHandleInformation (handles->in,  HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
  SetHandleInformation (handles->out, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
  SetHandleInformation (handles->err, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
}

/* Close the NUL handles opened by sps_resolve_stdio_handles for SILENCE
   streams; pipe ends remain owned by the caller. */
static void
sps_close_silence_handles (const sps_stdio_spec_t *stdio,
                           const sps_stdio_handles_t *handles)
{
  if (stdio->stdin_mode == SPS_STDIO_SILENCE)  CloseHandle (handles->in);
  if (stdio->stdout_mode == SPS_STDIO_SILENCE) CloseHandle (handles->out);
  if (stdio->stderr_mode == SPS_STDIO_SILENCE) CloseHandle (handles->err);
}
