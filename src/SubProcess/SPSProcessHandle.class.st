"
I am the Smalltalk-side handle to a spawned child OS process. I wrap the opaque
process token returned by the native spawn shim: the real OS process id on Unix
or the process HANDLE on Windows, both passed back to the shim for waiting and
killing.

I encapsulate the child's exit lifecycle. A wait either blocks until the child
exits (#waitForExit) or probes it once (#pollForExit); once the exit status is
known I decode and cache an exit code. A child is reaped at most once (on
Windows this closes the underlying HANDLE); after that, further waits answer the
cached exit code without touching the shim.

My Smalltalk side stays fully platform-agnostic: the shim owns every platform
detail.
"
Class {
	#name : #SPSProcessHandle,
	#superclass : #Object,
	#instVars : [
		'value',
		'exitCode',
		'isReaped'
	],
	#category : #SubProcess
}

{ #category : #'ffi - library' }
SPSProcessHandle >> ffiLibrary [

	^ SPSSpawnLibrary uniqueInstance
]

{ #category : #'instance creation' }
SPSProcessHandle class >> value: anInteger [

	^ self new initializeValue: anInteger
]

{ #category : #'api - accessing' }
SPSProcessHandle >> exitCode [

	"Answer the decoded exit code of the child, or nil while it is still running
	 or if it did not exit normally."

	^ exitCode
]

{ #category : #initialization }
SPSProcessHandle >> initializeValue: anInteger [

	value := anInteger.
	exitCode := nil.
	isReaped := false
]

{ #category : #'api - testing' }
SPSProcessHandle >> isReaped [

	"True if the child's exit status has been read (reaped). Once true, the child
	 process has been collected and, on Windows, its HANDLE closed."

	^ isReaped
]

{ #category : #'api - lifecycle' }
SPSProcessHandle >> pollForExit [

	"Answer true if the child has exited, decoding and caching its exit code as a
	 side effect. Non-blocking: answers false immediately while the child runs."

	| status |
	isReaped ifTrue: [ ^ true ].
	status := self waitStatusWithBlock: 0.
	status isNil ifTrue: [ ^ false ].
	self reapedWithStatus: status.
	^ true
]

{ #category : #'api - lifecycle' }
SPSProcessHandle >> terminate [

	"Ask the OS to kill the child (SIGKILL on Unix, TerminateProcess on Windows)
	 without reaping it; a later wait/reap collects it and closes the underlying
	 handle."

	self ffiLibrary killProcess: value
]

{ #category : #'api - lifecycle' }
SPSProcessHandle >> waitForExit [

	"Block until the child exits, then decode, cache and answer its exit code.
	 Answers the already-cached exit code if the child was reaped earlier."

	isReaped ifTrue: [ ^ exitCode ].
	self reapedWithStatus: (self waitStatusWithBlock: 1).
	^ exitCode
]

{ #category : #private }
SPSProcessHandle >> reapedWithStatus: aWaitStatus [

	exitCode := self decodeExitCodeFromWaitStatus: aWaitStatus.
	isReaped := true
]

{ #category : #private }
SPSProcessHandle >> waitStatusWithBlock: aBlock [

	"Answer the raw POSIX-like wait status if the child exited, or nil while it
	 is still running (poll mode) or on error."

	| result statusBuffer |
	statusBuffer := ByteArray new: 4.
	result := self ffiLibrary
		waitProcess: value
		block: aBlock
		statusBuffer: statusBuffer.
	result = 1 ifTrue: [ ^ statusBuffer integerAt: 1 size: 4 signed: true ].
	^ nil
]

{ #category : #private }
SPSProcessHandle >> decodeExitCodeFromWaitStatus: anInteger [

	"Decode a child wait status following the POSIX WIFEXITED/WEXITSTATUS
	 rules: a normal exit yields the low 8 bits of the shifted status; any
	 other termination (e.g. killed by a signal) has no simple exit code, so
	 we answer nil (matching GLib's behaviour of reporting no exit code)."

	(anInteger bitAnd: 16r7F) = 0 ifTrue: [ ^ (anInteger bitShift: -8) bitAnd: 16rFF ].
	^ nil
]
