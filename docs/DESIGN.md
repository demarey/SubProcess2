# SubProcess — Design Notes

This document explains the global machinery of the Pharo `SubProcess` package and
the design choices (and tradeoffs) behind it. The main driver for the current
architecture was **removing the GLib / GIO dependency** (former `GSubprocess`
usage) while **keeping the public Smalltalk API unchanged**. The test suite was
left untouched on purpose: it is the contract that proves the API is preserved
(run the same tests against the new native backend).

## Global machinery

The package is organised in three layers:

```
┌────────────────────────────  Smalltalk  ────────────────────────────┐
│                                                                      │
│  SPSProcessConfiguration   (shared configuration: sync/async,        │
│                             command+args, cwd, encoding, collect)   │
│        │                       │                                     │
│        ▼                       ▼                                     │
│  SPSProcess (sync)      SPSAsyncProcess (async)                      │
│        └────────────── SPSAbstractProcess ──────────────┘            │
│                        (shared pipe/args/exit helpers)               │
│                                │                                     │
│        SPSPipeReader · SPSPipeWriter (line split + collect)          │
│                                │                                     │
│                        SPSSpawnLibrary (FFI)                          │
└────────────────────────────────┼─────────────────────────────────────┘
                                 ▼
┌────────────────────────────  native/ (C shim)  ──────────────────────┐
│  sps_pipe        — create a pipe wired for a child stdio role        │
│  sps_spawn       — posix_spawn (Unix) / CreateProcess (Windows)      │
│  sps_read/write/close — move bytes on a pipe descriptor              │
│  sps_wait        — poll or block for child exit (waitpid / WaitFor…) │
│  sps_kill        — SIGKILL (Unix) / TerminateProcess (Windows)       │
└──────────────────────────────────────────────────────────────────────┘
```

`BaselineOfSubProcess` now requires only the package itself (+ `SubProcess-Tests`).

## The spawn contract

The bulk of the mechanism is a small C shim so that nothing platform-specific
lives in Smalltalk:

* **Pipes are created by the shim** (`sps_pipe`) — one for stdin, one for
  stdout, one for stderr. On Unix the descriptors are plain `int` fds; on
  Windows they are `HANDLE`s. Both are expressed to Smalltalk as platform-sized
  unsigned integers (an `sps_fd_t`), so the Smalltalk code is identical on every
  platform. The *child-facing* descriptor of each is passed to `sps_spawn`,
  which wires it to fd 0/1/2 in the child (and makes it inheritable on
  Windows). The parent keeps the opposite ends for its own reads/writes.
* **argv is a single NUL-separated blob**: `"prog\0arg1\0arg2\0"`. Using NUL as
  the separator means **no escaping is ever needed**, and a Pharo `String` can be
  marshalled to the C side directly. `args_len` is the blob's byte size (it
  contains embedded NULs, so it is not a C string).
* **All I/O goes through the shim.** `sps_read` transparently handles the
  Unix `O_NONBLOCK` retry convention and the Windows `PeekNamedPipe` +
  `ReadFile` emulation (returning 0 on broken-pipe EOF, −1 when no data is
  currently available). `sps_close`, `sps_wait` and `sps_kill` abstract the
  remaining platform differences, including encoding exit codes into a
  POSIX-like wait status on Windows so the shared `decodeExitCodeFromWaitStatus:`
  works unmodified. There is no Unix/Windows branching in Smalltalk.
* **One real OS pid on every platform** (Unix pid or Windows `CreateProcess`
  pid). The rest of the package treats exit and wait handling uniformly via
  `sps_wait`-based polling and `decodeExitCodeFromWaitStatus:`.
* **The caller must close its own copy of each child-facing descriptor** after a
  successful spawn (the read end of the stdin pipe and the write ends of the
  stdout/stderr pipes); otherwise the parent's read ends never see EOF. This is
  the caller's responsibility, not the shim's, and is done in `spawnProcess` /
  `spawn`.

## Sync path — `SPSProcess`

`SPSProcess run` blocks until the child exits:

1. Create the three pipes, build the argv blob and cwd (`workingDirectory
   fullName`, not `asString`).
2. `sps_spawn` the child, then close the parent's child-facing fds.
3. Put the parent stdout/stderr fds in non-blocking mode and **read each pipe to
   EOF** (`readToEndFromFd:`): a negative `read` means no data yet (yield and
   retry), `0` means EOF (stop). Raw bytes accumulate into a `ByteArray`.
4. Blocking `waitpid(pid, options: 0)`; decode the wait status into the exit
   code.

This gives a flat blocking API: `run`, `stdOut`, `stdErr`, `exitCode`,
`isSpawnSuccess`, `isComplete`.

## Async path — `SPSAsyncProcess`

`SPSAsyncProcess run` returns immediately and lets the child run in the
background:

* A **watcher process** is forked (`forkAt:` background priority,
  `'SubProcess-completion-watch'`). Each tick it **pumps** the stdout/stderr
  pipes and **polls** the child with a non-blocking `sps_wait` (block 0),
  sleeping ~3 ms when nothing is ready.
* `pumpOutput` reads available bytes and feeds each `SPSPipeReader`, which splits
  them into lines. Depending on configuration, lines go to an `outputLineDo:`
  subscriber and/or a collector `WriteStream` backing `stdOut`/`stdErr`; the raw
  readers also serve `stdOutChannel`/`stdErrChannel`. All pipe I/O (read/close)
  goes through `SPSSpawnLibrary`, so the reader/writer code paths are identical
  on every platform.
* **Completion** is announced only after the pipes are drained to EOF
  (`drainOutputToEof`), so collected output is complete: set `exitCode`, signal a
  `completionSemaphore`, set `isComplete`, then `announceCompleted`.
* `runAndWaitTimeOut:` waits on the semaphore; on timeout it calls `terminate`.
* `terminate` **hard-kills** the child (`SPSProcessControl terminatePid:` →
  SIGKILL on Unix, `TerminateProcess` on Windows, matching GLib's
  `g_subprocess_force_exit`), then does a cooperative shutdown: sets
  `stopRequested` so the watcher loop exits deterministically, reaps (blocking
  `sps_wait`), closes the channels, and marks complete/signals.

## Design choices & tradeoffs

* **C-shim package boundary instead of pure FFI.** Keeping argument
  generation, escaping, and platform-specific spawn logic in C removes a large
  class of bugs (and the GLib link) from Smalltalk. The cost is a small native
  build artifact (`libsps_spawn.{dylib,so}` / `sps_spawn.dll`).
* **NUL-separated argv blob vs. shell-like quoting.** No escaping/quoting edge
  cases, and trivial FFI marshalling. Slight cost: arguments cannot be read as a
  plain C string, hence the explicit length.
* **Background polling watcher vs. ThreadedFFI blocking readers or `select()`.**
  A single forked watcher that polls non-blocking fds plus non-blocking
  `sps_wait` is simple and fully portable across Unix/Windows. Tradeoffs: a
  small periodic CPU burn (~every 3 ms) and output latency of roughly one poll
  tick. It avoids the complexity (and one thread per channel) of ThreadedFFI;
  `select()` was not exposed through the shim to keep the FFI surface minimal.
* **Real OS pid everywhere.** Uniform exit/wait handling across platforms.
* **Uniform pipe I/O in the shim.** Because Windows uses `HANDLE`s while Unix
  uses `int` fds, all pipe I/O (create, read, write, close) and lifecycle
  (wait, kill) is delegated to the shim behind the opaque `sps_fd_t` type. The
  Smalltalk layer holds no platform-specific fds at all, which is what lets the
  same code run on Unix and Windows.
* **Hard-kill on timeout (async and sync), matching GLib `forceExit`.** Async
  `terminate` sends SIGKILL/`TerminateProcess`, then the shutdown sequence
  (stop + reap + close) is cooperative so the watcher exits cleanly and
  `runAndWaitTimeOut:` never hangs. Sync `terminate` kills the same way
  (`SPSProcessControl terminatePid:`) and is a no-op once complete, so it is safe
  to call in a `tearDown`. Caveat: SIGKILL cannot interrupt a process
  stuck in uninterruptible sleep, but callers still return because
  `isComplete`/the semaphore are set regardless of whether the child was reaped.

## A recorded lesson

`ByteArray >> copyFrom: index + 1` returns the **whole array** rather than the
tail slice, which caused an infinite loop in line extraction
(`SPSPipeReader >> extractPendingLines`). The code therefore uses the explicit two-argument
`copyFrom: start to: stop` form. Worth remembering when slicing `ByteArray`s in
Pharo.

## Build & run

```bash
cd native && make            # cc; libsps_spawn.dylib on macOS, .so on Linux
cd native && make selftest   # optional end-to-end C self-test (no GLib)
mingw32-make CC=gcc          # Windows via MinGW → sps_spawn.dll
```

Copy the produced shared library where the VM can load it, then load the package
in Pharo via the Metacello baseline and run the tests:

* `SyncSubProcessTest`   — 6 tests
* `ASyncSubProcessTest`  — 8 tests

Both suites pass against the native shim on macOS. On Windows the shim is
cross-compiled with MinGW (compilation-validated); the Smalltalk I/O layer has
no platform branching, and Windows support is verified through CI.
