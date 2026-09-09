"
I allow to spawn child OS processes syncronously.
Execution will be blocked until the child process completion.

I use SPSProcessConfiguration to configure myself.
"
Class {
	#name : #SPSProcess,
	#superclass : #SPSAbstractProcess,
	#instVars : [
		'stdOut',
		'stdErr',
		'isSpawnSuccess',
		'error',
		'processHandle'
	],
	#category : #SubProcess
}

{ #category : #constants }
SPSProcess class >> readPollDelay [

	"Delay while yielding between non-blocking reads of a child pipe."

	^ 2 milliSeconds
]

{ #category : #'api - accessing' }
SPSProcess >> error [

	^ error
]

{ #category : #private }
SPSProcess >> errorMessage: message errorCode: errorCode domainString: domainString [

	error := SPSError
		message: (message decodeWith: self configuration encoding)
		code: errorCode
		domainString: domainString
]

{ #category : #'api - accessing' }
SPSProcess >> exitCode [

	^ processHandle ifNotNil: [ processHandle exitCode ]
]

{ #category : #'api - testing' }
SPSProcess >> isSpawnSuccess [

	^ isSpawnSuccess
]

{ #category : #'api - running' }
SPSProcess >> run [

	self spawn.
	isComplete := true.
	self isSpawnSuccess ifFalse: [ self error signal ]
]

{ #category : #'api - accessing' }
SPSProcess >> stdErr [

	^ stdErr ifNil: [ '' ]
]

{ #category : #private }
SPSProcess >> stdErr: aByteArray [

	stdErr := aByteArray ifNotNil: [ aByteArray decodeWith: self configuration encoding ]
]

{ #category : #'api - accessing' }
SPSProcess >> stdOut [

	^ stdOut ifNil: [ '' ]
]

{ #category : #private }
SPSProcess >> stdOut: aByteArray [

	stdOut := aByteArray ifNotNil: [ aByteArray decodeWith: self configuration encoding ]
]

{ #category : #private }
SPSProcess >> isSpawnSuccess: aBoolean [

	isSpawnSuccess := aBoolean
]

{ #category : #'api - running' }
SPSProcess >> terminate [

	"Kill the child process if it is still running. No-op once complete, so it
	 can safely be called in a tearDown after #run returned."

	isComplete ifTrue: [ ^ self ].
	processHandle ifNotNil: [ processHandle terminate ]
]

{ #category : #private }
SPSProcess >> readToEndFromFd: aFd [

	"Read a non-blocking pipe descriptor until EOF (the child has closed its
	 end, i.e. exited), collecting the raw bytes. A negative read result means
	 no data is currently available, so we briefly yield and retry; EOF (0)
	 stops the loop. Returns a ByteArray."

	| library chunk output done count |
	library := self ffiLibrary.
	chunk := ByteArray new: self class outputReadBufferSize.
	output := ByteArray new: 0.
	done := false.

	[ done ] whileFalse: [
		count := library read: aFd buffer: chunk size: chunk size.
		count > 0
			ifTrue: [ output := output, (chunk first: count) ]
			ifFalse: [
				count = 0
					ifTrue: [ done := true ]
					ifFalse: [ (self class readPollDelay) asDelay wait ] ] ].
	^ output
]

{ #category : #private }
SPSProcess >> spawn [

	| stdinPipe stdoutPipe stderrPipe
	  childStdin childStdout childStderr
	  parentStdin parentStdout parentStderr
	  argsBlob cwd errBuf spawnResult |

	stdinPipe := self newPipeFor: #stdin.
	stdoutPipe := self newPipeFor: #stdout.
	stderrPipe := self newPipeFor: #stderr.
	(stdinPipe isNil or: [ stdoutPipe isNil or: [ stderrPipe isNil ] ])
		ifTrue: [
			{ stdinPipe. stdoutPipe. stderrPipe } do: [ :each | each ifNotNil: [ self closeFd: each first. self closeFd: each second ] ].
			self isSpawnSuccess: false.
			self errorMessage: 'Cannot create pipes' errorCode: 0 domainString: 'SubProcess'.
			^ self ].

	childStdin := stdinPipe second.
	parentStdin := stdinPipe first.
	childStdout := stdoutPipe second.
	parentStdout := stdoutPipe first.
	childStderr := stderrPipe second.
	parentStderr := stderrPipe first.

	argsBlob := self argsBlob.
	cwd := self configuration workingDirectory ifNotNil: [ :file | file fullName ].
	errBuf := ByteArray new: self class spawnErrorBufferSize.
	spawnResult := self ffiLibrary
		spawnStdin: childStdin
		stdout: childStdout
		stderr: childStderr
		args: argsBlob
		argsLength: argsBlob byteSize
		cwd: cwd
		error: errBuf
		errorLength: errBuf size.
	spawnResult <= self class spawnFailureBoundary
		ifTrue: [
			self closeAllPipeFds: {
				childStdin. parentStdin. childStdout. parentStdout. childStderr. parentStderr }.
			self isSpawnSuccess: false.
			self
				errorMessage: (self cStringBytesFrom: errBuf)
				errorCode: (0 - spawnResult)
				domainString: 'SubProcess' ]
		ifFalse: [
			self closeAllPipeFds: { childStdin. parentStdin. childStdout. childStderr }.
			self isSpawnSuccess: true.
			processHandle := SPSProcessHandle value: spawnResult.
			self ffiLibrary fdSetNonBlocking: parentStdout.
			self ffiLibrary fdSetNonBlocking: parentStderr.
			self stdOut: (self readToEndFromFd: parentStdout).
			self stdErr: (self readToEndFromFd: parentStderr).
			self closeAllPipeFds: { parentStdout. parentStderr }.
			processHandle waitForExit ]
]
