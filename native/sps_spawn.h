/*
 * sps_spawn.h
 *
 * Minimal OS-process spawn helper used by the Pharo SubProcess package.
 * It replaces the GLib g_spawn_* functionality with a tiny platform-specific
 * wrapper around posix_spawn (macOS/Linux) and CreateProcess (Windows), so the
 * package no longer depends on GLib.
 *
 * The caller (Smalltalk) creates the three pipes and passes the child-facing
 * descriptor of each:
 *   - child_stdin  : descriptor that becomes the child's stdin
 *                    (the read end of the parent's stdin pipe).
 *   - child_stdout : descriptor that becomes the child's stdout
 *                    (the write end of the parent's stdout pipe).
 *   - child_stderr : descriptor that becomes the child's stderr
 *                    (the write end of the parent's stderr pipe).
 * Each is dup2'd (Unix) / assigned via STARTUPINFO (Windows) to fd 0/1/2 in
 * the child. The parent keeps the opposite ends for its own reads/writes.
 *
 * args is the full program invocation as a single NUL-separated blob:
 *
 *   "prog\0arg1\0arg2\0"
 *
 * i.e. argv[0] followed by one string per argument, each terminated by a NUL
 * (the last argument also terminated by NUL). Using NUL as the separator means
 * no escaping is ever needed, and a String can be marshalled to this directly.
 * args_len is the blob's length in bytes (it may contain embedded NULs, so it
 * cannot be read as a C string).
 *
 * cwd may be NULL (inherit the parent's working directory).
 *
 * After a successful spawn, the caller MUST close its own copy of each
 * child-facing descriptor (the read end of the stdin pipe and the write ends
 * of the stdout/stderr pipes); otherwise the parent's read ends never see EOF.
 * This is the caller's responsibility, not the shim's.
 *
 * Return value:
 *   on success, a positive child identifier (the real OS pid on both Unix and
 *   Windows);
 *   on failure, a negated error number (< 0) and errbuf filled with a
 *   human-readable message (NUL-terminated, if errbuf_len > 0).
 */

#ifndef SPS_SPAWN_H
#define SPS_SPAWN_H

#include <stddef.h>
#include <stdint.h>

typedef uintptr_t sps_fd_t;

intptr_t sps_spawn (sps_fd_t child_stdin, sps_fd_t child_stdout,
                    sps_fd_t child_stderr,
                    const char *args, size_t args_len, const char *cwd,
                    char *errbuf, size_t errbuf_len);

/* Put a pipe descriptor into non-blocking mode so a reader can poll it
 * without deadlocking. Returns 0 on success, -1 on failure. */
int sps_fd_set_nonblocking (sps_fd_t fd);

#endif
