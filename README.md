# SubProcess [![Build Status](https://github.com/demarey/SubProcess/actions/workflows/main.yml/badge.svg)](https://github.com/demarey/SubProcess/actions/workflows/main.yml)

This project allows to run OS sub processes from a Pharo image.
It uses GLib IO library to spawn processes through FFI calls.
SubProcess offers a high-level API, OS-agnostic API to run easily processes from your Pharo code. Windows, Linux and Mac Os are supported!

## Examples

### Run a simple command (one-liner)
`SubProcess run:` builds a configuration, runs it synchronously and returns the
process, so its output and status are directly available:
```smalltalk
process := SubProcess run: '/bin/ls'.
out := process stdOut.
```
You can pass arguments too:
```smalltalk
process := SubProcess run: '/bin/ls' arguments: #('/etc').
```

### Run a simple command (fluent configuration)
```smalltalk
process := SPSProcessConfiguration new
  command: '/bin/ls';
  asSyncProcess.
process run.
 ```
  
```smalltalk
process := SPSProcessConfiguration new
  command: 'C:\Windows\System32\systeminfo.exe';
  asSyncProcess.
process run.
```
  
### Run a command and getting the output
```smalltalk
process := SPSProcessConfiguration new
  command: '/bin/ls';
  asSyncProcess.
process run.
  
out := process stdOut.
err := process stdErr.
```
  
### Set the working directory
```smalltalk
process := SPSProcessConfiguration new
  workingDirectory: '/etc';
  command: '/bin/ls';
  asSyncProcess.
	
process run.
```
  
### Give arguments
```smalltalk
process := SPSProcessConfiguration new
  command: '/bin/ls';
  arguments: #('/etc');
  asSyncProcess.
	
process run.
```
  
### Use a shell to run the command
```smalltalk
process := SPSProcessConfiguration new
  workingDirectory: 'C:\';
  windowsShellCommand;
  addArgument: 'dir';
  asSyncProcess.
  
process run.
```

## Running asynchroneous processes

`start` processes return immediately after the child is spawned: execution resumes without
waiting for the child to terminate. This is handy to run long-running commands or several
processes in parallel. You later block on `wait` (until completion) or `waitFor:` (with a
timeout).

### Start a command asynchroneously with the facade
`SubProcess start:` launches the child and returns the running process at once. Output is
auto-collected by default, so `stdOut` / `stdErr` are available after `wait`:
```smalltalk
process := SubProcess start: '/bin/sh' arguments: { '-c'. 'seq 1 1000' }.
process whenCompletedDo: [ :aProcess |
  Transcript show: 'exit code: ', aProcess exitCode asString; cr ].
process wait.                          "block until done"
out := process stdOut.
```

### Start a command asynchroneously (fluent configuration)
```smalltalk
process := SPSProcessConfiguration new
  command: '/bin/ls';
  asAsyncProcess.
process start.
```

### Know when the process completed
Register a callback invoked when the child process exits:
```smalltalk
process := SPSProcessConfiguration new
  command: '/bin/sh';
  arguments: #('-c' 'sleep 2');
  asAsyncProcess.
process whenCompletedDo: [ :aProcess |
  Transcript show: 'exit code: ', aProcess exitCode asString; cr ].
process start.
```

### Reading the output with streams
By default no output is captured. Read directly from the process channels (blocking reads):
```smalltalk
process := SPSProcessConfiguration new
  command: '/bin/ls';
  asAsyncProcess.
process start.
out := process stdOutChannel readLine.
```
WARNING: if the child produces a lot of output, nothing reads the pipes: they fill up, the child
blocks writing and never finishes. Prefer `collectsOutput` or `outputLineDo:` for output-heavy
commands.

### Consuming the output line-by-line (streaming)
`outputLineDo:` evaluates a block for each output line as it is produced, without buffering the
whole output in memory. Ideal for large or infinite output:
```smalltalk
process := SPSProcessConfiguration new
  command: '/bin/sh';
  arguments: #('-c' 'seq 1 1000');
  asAsyncProcess.
process outputLineDo: [ :aLine | Transcript show: aLine; cr ].
process start.
```

### Auto-collecting the output
By default no output is captured. Call `collectsOutput` on the configuration to capture stdout
and stderr line-by-line in the background. (The `SubProcess start:` facade does this for you.)
The collected text is then available on `stdOut` / `stdErr`. When the process completes, the
output listeners are drained to EOF before completion is announced, so the collected output is
complete:
```smalltalk
process := SPSProcessConfiguration new
  command: '/bin/sh';
  arguments: #('-c' 'echo hello');
  collectsOutput;
  asAsyncProcess.
process start.
process waitFor: 2 seconds.
out := process stdOut.   "a String containing 'hello'"
```

### Waiting with a timeout
`wait` and `waitFor:` wait on an already-**started** process; they never launch one. `waitFor:`
waits up to the given duration for completion and kills the child if it did not finish in time.
It answers `true` on timeout, `false` otherwise. Calling them on a process that was not started
raises `SPSError`:
```smalltalk
process := SPSProcessConfiguration new
  command: '/bin/sleep';
  arguments: #('30');
  asAsyncProcess.
process start.
self assert: (process waitFor: 1 second).
```

### Terminating a running process
```smalltalk
process := SubProcess start: '/bin/sleep' arguments: { '30' }.
process terminate.
```


## How asynchroneous processes work internally

An async process (`asAsyncProcess`, launched with `start`) spawns the child and returns
immediately; a few background elements then orchestrate its lifecycle. Concretely, when a process
is `start`ed, the following happen:

1. **Main (caller) thread** — `start` spawns the child via `g_spawn_async_with_pipes` with
   `G_SPAWN_DO_NOT_REAP_CHILD` (so our watch — and not GLib — reaps the child), then sets up the
   output reading and the completion watch, and returns at once. The caller never blocks unless
   it explicitly calls `wait`, `waitFor:` or reads a channel.

2. **Completion-watch worker** — a dedicated background Pharo process iterates the GLib default
   main context until `isComplete` is set. This is what dispatches GLib's child-watch callback,
   so completion is detected even in a headless image with no running GTK event loop. When the
   child exits, the callback records the exit code.

3. **Output listener threads** — one per channel (stdout, stderr). Each is a forked Pharo process
   (`Channel read listener: ...`) that runs a `GIOChannelReadLineListener`: it blocks reading lines
   from its pipe with `g_io_channel_read_line` (on a ThreadedFFI `TFWorker` thread) until EOF, and
   dispatches each line to the configured action. These threads are what keep the pipes drained, so
   a child producing lots of output never deadlocks on a full pipe. They are only started when
   output is read, i.e. with `collectsOutput` or `outputLineDo:` (message `outputsBeingRead`).

4. **Drain & completion** — when the child exits, `beCompleted:` first lets the listener threads
   drain their pipes to EOF (waiting on a fixed 5 s timeout, with a diagnostic if it expires), then
   closes the process, sets `isComplete`, and announces completion. This guarantees `stdOut`/
   `stdErr` are complete when `whenCompletedDo:` fires or `waitFor:` returns.

Because these steps run on different threads/processes, the streams are consumed asynchronously:
when you poll `isComplete`, always assume data may still be settling unless you wait on the actual
condition you care about (see `waitFor:within:` used by the tests).

## Getting the status of the process
### Know if the process has completed its execution
```smalltalk
process := SPSProcessConfiguration new
  command: '/bin/ls';
  asSyncProcess.
process run.
self assert: process isComplete.
```
### Asynchroneous processes: isComplete vs wasTerminated
With async processes, `isComplete` tells whether the child has finished running, whatever the
reason. Use `wasTerminated` to know if that finish was caused by your own `terminate` call
(e.g. because of a timeout):
```smalltalk
process := SPSProcessConfiguration new
  command: '/bin/sleep';
  arguments: #('30');
  asAsyncProcess.
timedOut := process waitFor: 1 second.
self assert: timedOut.
self assert: process isComplete.      "the process finished"
self assert: process wasTerminated.   "...because we killed it"
```
- `isComplete = true` and `wasTerminated = false` → the child exited by itself (normal or signal exit).
- `isComplete = true` and `wasTerminated = true` → the child was killed by the caller.
- `isComplete = false` → still running (never terminated).
### Know if the spawn of the process is sucessful (no error)
```smalltalk
process := SPSProcessConfiguration new
  command: '/bin/ls';
  asSyncProcess.
process run.
self assert: process isSpawnSuccess.
```
### Know if the process exited successfully (exit code 0)
```smalltalk
process := SPSProcessConfiguration new
  command: '/bin/ls';
  asSyncProcess.
process run.
self assert: process isExitSuccess.
```
### Getting error if the spawn of the process failed
```smalltalk
process := SPSProcessConfiguration new
  command: '/bin/ls';
  asSyncProcess.
[ process run ]
on: SPSError
do: [ :error | error messageText inspect ]
```

## Encoding
When running a command that will give you back some output (standard output or standard error), you will get an encoded String (a byte array) that needs to be decoded. SubProcess cannot guess what will be the encoding as many encodings are used worldwide. One commonly used encoding is utf-8 on unix-like systems. On Windows, different encondings are used.
SubProcess configure a default encoding (`utf-8` on unix-like systems and `cp-850` on Windows) for convenience. Do not forget you could need a different encoding. If so, you can configure it before running the process:
```smalltalk
process := SPSProcessConfiguration new
  encoding: 'ISO-8859-2'
  command: '/bin/ls';
  asSyncProcess.
process run.
out := process stdOut.
```
