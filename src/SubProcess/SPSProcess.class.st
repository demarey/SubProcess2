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
		'exitCode',
		'pid'
	],
	#category : #SubProcess
}

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

	^ exitCode
]

{ #category : #private }
SPSProcess >> exitCode: anInteger [

	exitCode := anInteger
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
	pid ifNotNil: [ SPSProcessControl terminatePid: pid ]
]

{ #category : #private }
SPSProcess >> readToEndFromFd: aFd [

	"Read aNonBlocking pipe descriptor until EOF (the child has closed its
	 end, i.e. exited), collecting the raw bytes. A negative read result means
	 no data is currently available, so we briefly yield and retry; EOF (0)
	 stops the loop. Returns a ByteArray."

	| libc chunk output done count |
	libc := LibC uniqueInstance.
	chunk := ByteArray new: 65536.
	output := ByteArray new: 0.
	done := false.

	[ done ] whileFalse: [
		count := libc read: aFd buffer: chunk size: chunk size.
		count > 0
			ifTrue: [ output := output, (chunk first: count) ]
			ifFalse: [
				count = 0
					ifTrue: [ done := true ]
					ifFalse: [ (2 milliSeconds) asDelay wait ] ] ].
	^ output
]

{ #category : #private }
SPSProcess >> spawn [

	| stdinPipe stdoutPipe stderrPipe
	  childStdin childStdout childStderr
	  parentStdin parentStdout parentStderr
	  argsBlob cwd errBuf spawnResult |

	stdinPipe := self newPipeFds.
	stdoutPipe := self newPipeFds.
	stderrPipe := self newPipeFds.
	(stdinPipe isNil or: [ stdoutPipe isNil or: [ stderrPipe isNil ] ])
		ifTrue: [
			{ stdinPipe. stdoutPipe. stderrPipe } do: [ :each | each ifNotNil: [ self closeFd: each first. self closeFd: each second ] ].
			self isSpawnSuccess: false.
			self errorMessage: 'Cannot create pipes' errorCode: 0 domainString: 'SubProcess'.
			^ self ].

	childStdin := stdinPipe first.
	parentStdin := stdinPipe second.
	childStdout := stdoutPipe second.
	parentStdout := stdoutPipe first.
	childStderr := stderrPipe second.
	parentStderr := stderrPipe first.

	argsBlob := self argsBlob.
	cwd := self configuration workingDirectory ifNotNil: [ :file | file fullName ].
	errBuf := ByteArray new: 1024.
	spawnResult := SPSSpawnLibrary uniqueInstance
		spawnStdin: childStdin
		stdout: childStdout
		stderr: childStderr
		args: argsBlob
		argsLength: argsBlob byteSize
		cwd: cwd
		error: errBuf
		errorLength: errBuf size.

	spawnResult <= 0
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
			pid := spawnResult.
			SPSSpawnLibrary uniqueInstance fdSetNonBlocking: parentStdout.
			SPSSpawnLibrary uniqueInstance fdSetNonBlocking: parentStderr.
			self stdOut: (self readToEndFromFd: parentStdout).
			self stdErr: (self readToEndFromFd: parentStderr).
			self closeAllPipeFds: { parentStdout. parentStderr }.
			self waitExitStatusOfPid: spawnResult ]
]

{ #category : #private }
SPSProcess >> waitExitStatusOfPid: aPid [

	| libc statusBuffer decoded |
	libc := LibC uniqueInstance.
	statusBuffer := ByteArray new: 4.
	libc waitpid: aPid status: statusBuffer options: 0.
	decoded := statusBuffer integerAt: 1 size: 4 signed: true.
	self exitCode: (self decodeExitCodeFromWaitStatus: decoded)
]
