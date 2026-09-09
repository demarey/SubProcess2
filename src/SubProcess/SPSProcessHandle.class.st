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
	#traits : 'SPSTLibrary',
	#classTraits : 'SPSTLibrary classTrait',
	#instVars : [
		'value',
		'exitCode',
		'isReaped'
	],
	#category : #SubProcess
}

{ #category : #constants }
SPSProcessHandle class >> exitCodeLowerMask [

	"Bits holding the exit code within a wait status (WEXITSTATUS)."

	^ 16rFF
]

{ #category : #constants }
SPSProcessHandle class >> exitCodeShiftBits [

	"Shift from a wait status to its exit-code bits (WEXITSTATUS)."

	^ 8
]

{ #category : #constants }
SPSProcessHandle class >> waitSucceeded [

	"Value sps_wait answers when the wait completed and a raw wait status has
	 been written into the status buffer (vs 0 still running, -1 on error)."

	^ 1
]

{ #category : #constants }
SPSProcessHandle class >> signalTerminationMask [

	"Low 7 bits of a wait status: nonzero when the child was terminated by a
	 signal (WIFEXITED test)."

	^ 16r7F
]

{ #category : #constants }
SPSProcessHandle class >> waitBlockMode [

	"Blocking mode for sps_wait (blocks until the child exits)."

	^ 1
]

{ #category : #constants }
SPSProcessHandle class >> waitPollMode [

	"Poll mode for sps_wait (answers immediately, 0 while the child runs)."

	^ 0
]

{ #category : #constants }
SPSProcessHandle class >> waitStatusBufferSize [

	"Size in bytes of the buffer receiving a wait status (a native int)."

	^ 4
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
	status := self waitStatusWithBlock: self class waitPollMode.
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
	self reapedWithStatus: (self waitStatusWithBlock: self class waitBlockMode).
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
	statusBuffer := ByteArray new: self class waitStatusBufferSize.
	result := self ffiLibrary
		waitProcess: value
		block: aBlock
		statusBuffer: statusBuffer.
	result = self class waitSucceeded ifTrue: [ ^ statusBuffer integerAt: 1 size: self class waitStatusBufferSize signed: true ].
	^ nil
]

{ #category : #private }
SPSProcessHandle >> decodeExitCodeFromWaitStatus: anInteger [

	"Decode a child wait status following the POSIX WIFEXITED/WEXITSTATUS
	 rules: a normal exit yields the low 8 bits of the shifted status; any
	 other termination (e.g. killed by a signal) has no simple exit code, so
	 we answer nil (matching GLib's behaviour of reporting no exit code)."

	(anInteger bitAnd: self class signalTerminationMask) = 0
		ifTrue: [ ^ (anInteger bitShift: self class exitCodeShiftBits negated) bitAnd: self class exitCodeLowerMask ].
	^ nil
]
