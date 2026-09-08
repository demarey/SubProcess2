"
I am an FFI library wrapping the native spawn shim (`libsps_spawn` on Unix,
`sps_spawn.dll` on Windows) that replaces the former GLib `GSubprocess`
dependency. I expose:

- `sps_spawn` to launch a child process, wiring the given standard-stream
  descriptors and working directory, and reporting failures with a negated
  error number plus a human-readable message;
- `sps_fd_set_nonblocking` to put a pipe descriptor into polling mode.

The child identifier returned is the real OS process id on every platform, so
the rest of the package can treat it uniformly.
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
SPSSpawnLibrary >> fdSetNonBlocking: aFd [

	OSPlatform current isWindows ifTrue: [ ^ self ].

	^ self ffiCall: #(int sps_fd_set_nonblocking(int aFd))
]

{ #category : #ffi }
SPSSpawnLibrary >> spawnStdin: aStdinFd stdout: aStdoutFd stderr: aStderrFd args: anArgsBlob argsLength: anArgsLength cwd: aCwdString error: anErrBuf errorLength: anErrBufLength [

	OSPlatform current isWindows
		ifTrue: [
			^ self
				spawnWindowsStdin: aStdinFd
				stdout: aStdoutFd
				stderr: aStderrFd
				args: anArgsBlob
				argsLength: anArgsLength
				cwd: aCwdString
				error: anErrBuf
				errorLength: anErrBufLength ]
		ifFalse: [
			^ self
				spawnUnixStdin: aStdinFd
				stdout: aStdoutFd
				stderr: aStderrFd
				args: anArgsBlob
				argsLength: anArgsLength
				cwd: aCwdString
				error: anErrBuf
				errorLength: anErrBufLength ]
]

{ #category : #ffi }
SPSSpawnLibrary >> spawnUnixStdin: aStdinFd stdout: aStdoutFd stderr: aStderrFd args: anArgsBlob argsLength: anArgsLength cwd: aCwdString error: anErrBuf errorLength: anErrBufLength [

	^ self ffiCall: #(long sps_spawn(int aStdinFd, int aStdoutFd, int aStderrFd, const char* anArgsBlob, size_t anArgsLength, const char* aCwdString, char* anErrBuf, size_t anErrBufLength))
]

{ #category : #ffi }
SPSSpawnLibrary >> spawnWindowsStdin: aStdinFd stdout: aStdoutFd stderr: aStderrFd args: anArgsBlob argsLength: anArgsLength cwd: aCwdString error: anErrBuf errorLength: anErrBufLength [

	^ self ffiCall: #(long sps_spawn(void* aStdinFd, void* aStdoutFd, void* aStderrFd, const char* anArgsBlob, size_t anArgsLength, const char* aCwdString, char* anErrBuf, size_t anErrBufLength))
]
