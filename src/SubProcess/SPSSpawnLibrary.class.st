"
I am an FFI library wrapping the native spawn shim (`libsps_spawn` on Unix,
`sps_spawn.dll` on Windows) that replaces the former GLib `GSubprocess`
dependency. I expose the whole process I/O surface the package needs:

- `newPipe:` to create an anonymous pipe wired for a child role;
- `spawnStdio:args:cwd:error:errorLength:` to launch a child, wiring its
  standard streams (per SPSStdioSpec) and working directory;
- `read:buffer:size:` / `write:buffer:size:` / `closeFd:` / `fdSetNonBlocking:`
  to move bytes on a pipe descriptor;
- `waitProcess:block:status:` to wait for a child;
- `killProcess:` to terminate a child.

Descriptors (`sps_fd_t`) are unsigned integers that look like Unix file
descriptors on Unix and HANDLEs on Windows; the shim owns every platform
detail, so this class is fully platform-agnostic. The token returned by
`spawnStdin:...` is an opaque extended integer: the real OS process id on Unix
and the process HANDLE on Windows, passed back to `waitProcess:` /
`killProcess:`. SPSProcessHandle wraps it and exposes the wait/kill lifecycle.
"
Class {
	#name : #SPSSpawnLibrary,
	#superclass : #FFILibrary,
	#category : #SubProcess
}

{ #category : #accessing }
SPSSpawnLibrary >> macLibraryName [

	^ 'libsps_spawn.dylib'
]

{ #category : #accessing }
SPSSpawnLibrary >> unix64LibraryName [

	^ 'libsps_spawn.so'
]

{ #category : #accessing }
SPSSpawnLibrary >> unix32LibraryName [

	^ 'libsps_spawn.so'
]

{ #category : #accessing }
SPSSpawnLibrary >> win32LibraryName [

	^ 'sps_spawn.dll'
]

{ #category : #ffi }
SPSSpawnLibrary >> closeFd: aFd [

	^ self ffiCall: #(int sps_close(size_t aFd))
]

{ #category : #ffi }
SPSSpawnLibrary >> fdSetNonBlocking: aFd [

	^ self ffiCall: #(int sps_fd_set_nonblocking(size_t aFd))
]

{ #category : #ffi }
SPSSpawnLibrary >> killProcess: aProcessToken [

	^ self ffiCall: #(int sps_kill(longlong aProcessToken))
]

{ #category : #ffi }
SPSSpawnLibrary >> newPipe: aKind parent: aParentBuffer child: aChildBuffer [

	"Create an anonymous pipe whose child end is wired for the given role
	 (aKind: 0 stdin, 1 stdout, 2 stderr). On success writes the parent and
	 child `sps_fd_t` descriptors into the two supplied 8-byte external buffers
	 and answers 0; answers -1 on failure."

	^ self ffiCall: #(int sps_pipe(int aKind, void* aParentBuffer, void* aChildBuffer))
]

{ #category : #ffi }
SPSSpawnLibrary >> read: aFd buffer: aBuffer size: aCount [

	^ self ffiCall: #(long sps_read(size_t aFd, void* aBuffer, size_t aCount))
]

{ #category : #ffi }
SPSSpawnLibrary >> spawnStdio: aStdioSpec args: anArgsBlob argsLength: anArgsLength cwd: aCwdString error: anErrBuf errorLength: anErrBufLength [

	^ self ffiCall: #(longlong sps_spawn(SPSStdioSpec* aStdioSpec, const char* anArgsBlob, size_t anArgsLength, const char* aCwdString, char* anErrBuf, size_t anErrBufLength))
]

{ #category : #ffi }
SPSSpawnLibrary >> waitProcess: aProcessToken block: aBlock statusBuffer: aStatusBuffer [

	"Wait for the child identified by aProcessToken. Answers 1 once it has exited
	 (writing a wait status into the 4-byte aStatusBuffer), 0 while it is still
	 running in poll mode (aBlock false), and -1 on error. aBlock true blocks
	 until exit."

	^ self ffiCall: #(int sps_wait(longlong aProcessToken, int aBlock, int* aStatusBuffer))
]

{ #category : #ffi }
SPSSpawnLibrary >> write: aFd buffer: aBuffer size: aCount [

	^ self ffiCall: #(long sps_write(size_t aFd, void* aBuffer, size_t aCount))
]
