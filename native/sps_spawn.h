/*
 * sps_spawn.h
 *
 * Minimal OS-process spawn helper used by the Pharo SubProcess package.
 * It replaces the GLib g_spawn_* functionality with a tiny platform-specific
 * wrapper around posix_spawn (macOS/Linux) and CreateProcess (Windows), so the
 * package no longer depends on GLib.
 *
 * All pipe I/O needed to run a child with captured stdout/stderr lives here,
 * behind a uniform descriptor type (sps_fd_t) and a small set of functions, so
 * the Smalltalk side stays fully platform-agnostic:
 *
 *   sps_pipe  - create an anonymous pipe, wired for the requested child role,
 *   sps_spawn - launch a child with its stdio connected to three pipe ends,
 *   sps_read / sps_write / sps_close - move bytes on a pipe descriptor,
 *   sps_wait  - wait for a child (poll or block) and get a wait status,
 *   sps_kill  - terminate a running child (SIGKILL / TerminateProcess).
 *
 * On Unix sps_fd_t is an int file descriptor; on Windows it is a HANDLE. The
 * Smalltalk code manipulates these as unsigned integers only and lets this
 * shim own every platform-specific detail.
 */

#ifndef SPS_SPAWN_H
#define SPS_SPAWN_H

#include <stddef.h>
#include <stdint.h>

typedef uintptr_t sps_fd_t;

/* The role asked of an sps_pipe, i.e. which end must reach the child. */
typedef enum {
  SPS_PIPE_STDIN = 0,   /* child reads, parent writes */
  SPS_PIPE_STDOUT = 1,  /* child writes, parent reads */
  SPS_PIPE_STDERR = 2   /* child writes, parent reads */
} sps_pipe_kind_t;

/* Create an anonymous pipe for a child role. Writes the parent and child ends
 * into *out_parent / *out_child (the parent end is the one the caller uses for
 * its own reads/writes; the child end goes to sps_spawn). Returns 0 on
 * success, -1 on failure. */
int sps_pipe (int kind, sps_fd_t *out_parent, sps_fd_t *out_child);

/* Launch a child process, wiring child_stdin/out/err (child ends from
 * sps_pipe) to fds 0/1/2. args is the full invocation as a NUL-separated blob
 * ("prog\0arg1\0arg2\0"); args_len is its byte length (may contain embedded
 * NULs). cwd may be NULL to inherit the parent's directory.
 *
 * Returns an opaque process token on success: on Unix the real OS pid, on
 * Windows the CreateProcess HANDLE kept open for the child's lifetime. On
 * failure returns a negated error number and, if errbuf_len > 0, fills errbuf
 * with a NUL-terminated message.
 *
 * After a successful spawn the caller MUST close its own copy of each
 * child-facing end with sps_close; otherwise the parent's read ends never see
 * EOF. */
intptr_t sps_spawn (sps_fd_t child_stdin, sps_fd_t child_stdout,
                    sps_fd_t child_stderr,
                    const char *args, size_t args_len, const char *cwd,
                    char *errbuf, size_t errbuf_len);

/* Put a pipe descriptor into non-blocking mode so a reader can poll it without
 * deadlocking. On Windows this is a no-op (read readiness is handled inside
 * sps_read). Returns 0 on success, -1 on failure. */
int sps_fd_set_nonblocking (sps_fd_t fd);

/* Read up to len bytes from a pipe descriptor. Answers > 0 the number of bytes
 * read, 0 on end of stream (EOF), and -1 when no data is currently available
 * (EAGAIN) or on error. */
long sps_read (sps_fd_t fd, char *buf, size_t len);

/* Write up to len bytes to a pipe descriptor. Answers the number of bytes
 * written, or -1 on error. */
long sps_write (sps_fd_t fd, const char *buf, size_t len);

/* Close a pipe descriptor. Answers 0 on success, -1 on error. */
int sps_close (sps_fd_t fd);

/* Wait for the child identified by the token returned from sps_spawn. If block
 * is non-zero, blocks until the child exits; otherwise returns immediately.
 *
 * Answers 1 once the child has exited (writing a POSIX-like wait status into
 * *out_status that SPSAbstractProcess can decode with WIFEXITED/WEXITSTATUS
 * rules), 0 while the child is still running (poll mode), and -1 on error or
 * when the token is no longer valid (e.g. already reaped).
 *
 * On exit the shim reaps the child (on Windows this closes the handle held by
 * the token), so a given token should be waited on at most once. */
int sps_wait (intptr_t token, int block, int *out_status);

/* Terminate a running child (SIGKILL on Unix, TerminateProcess on Windows).
 * On Windows the handle held by the token is deliberately left open so a later
 * sps_wait can reap it. Answers 0 on success, -1 on failure. */
int sps_kill (intptr_t token);

#endif
