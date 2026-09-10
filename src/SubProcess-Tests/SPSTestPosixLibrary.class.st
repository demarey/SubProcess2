"
I expose the small set of libc functions needed by the POSIX-only tests that
observe the `#inherit` stdio policy through the real file descriptors of the
current process (see SyncSubProcessTest>>#testRunningCommandWithInheritedStdout
and ASyncSubProcessTest>>#testRunningCommandWithInheritedStdout).

A test temporarily redirects the caller's file descriptor 1 to a scratch file
(#open: + #dup2:to:), runs a child process that inherits it and writes a marker,
then restores the original descriptor (#dup2:to: again) so the image's standard
output is unaffected.
"
Class {
	#name : #SPSTestPosixLibrary,
	#superclass : #FFILibrary,
	#category : #'SubProcess-Tests'
}

{ #category : #'library name' }
SPSTestPosixLibrary >> macLibraryName [

	^ self class libcSharedLibraryName
]

{ #category : #'library name' }
SPSTestPosixLibrary >> unix64LibraryName [

	^ self class libcSharedLibraryName
]

{ #category : #'library name' }
SPSTestPosixLibrary >> unix32LibraryName [

	^ self class libcSharedLibraryName
]

{ #category : #'library name' }
SPSTestPosixLibrary class >> libcSharedLibraryName [

	^ OSPlatform current isMacOS
		ifTrue: [ 'libSystem.B.dylib' ]
		ifFalse: [ 'libc.so.6' ]
]

{ #category : #constants }
SPSTestPosixLibrary class >> oCreat [

	"O_CREAT: create the file if it does not already exist (macOS/Linux)."

	^ 512
]

{ #category : #constants }
SPSTestPosixLibrary class >> oRdwr [

	"O_RDWR: open for both reading and writing."

	^ 2
]

{ #category : #constants }
SPSTestPosixLibrary class >> oTrunc [

	"O_TRUNC: truncate the file to zero length upon open (macOS/Linux)."

	^ 1024
]

{ #category : #constants }
SPSTestPosixLibrary class >> oWronly [

	"O_WRONLY: open for writing only."

	^ 1
]

{ #category : #constants }
SPSTestPosixLibrary class >> stdOutFd [

	"File descriptor number of the process' standard output."

	^ 1
]

{ #category : #'private - ffi' }
SPSTestPosixLibrary >> close: fileDescriptor [

	^ self ffiCall: #(int close(int fileDescriptor))
]

{ #category : #'private - ffi' }
SPSTestPosixLibrary >> dup2: oldFileDescriptor to: newFileDescriptor [

	^ self ffiCall: #(int dup2(int oldFileDescriptor, int newFileDescriptor))
]

{ #category : #'private - ffi' }
SPSTestPosixLibrary >> open: pathName flags: flags mode: mode [

	^ self ffiCall: #(int open(const char * pathName, int flags, int mode))
]

{ #category : #'private - ffi' }
SPSTestPosixLibrary >> read: fileDescriptor buffer: buffer size: count [

	^ self ffiCall: #(long read(int fileDescriptor, void * buffer, unsigned long count))
]
