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
		message: (self decode: message)
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

	self spawnProcess.
	isComplete := true.
	self isSpawnSuccess ifFalse: [ self error signal ]
]

{ #category : #'api - accessing' }
SPSProcess >> stdErr [

	^ stdErr ifNil: [ '' ]
]

{ #category : #private }
SPSProcess >> stdErr: aByteArray [

	stdErr := aByteArray ifNotNil: [ self decode: aByteArray ]
]

{ #category : #'api - accessing' }
SPSProcess >> stdOut [

	^ stdOut ifNil: [ '' ]
]

{ #category : #private }
SPSProcess >> stdOut: aByteArray [

	stdOut := aByteArray ifNotNil: [ self decode: aByteArray ]
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

{ #category : #'private - spawning' }
SPSProcess >> handleSpawnError: aByteArrayOrString code: anInteger [

	self isSpawnSuccess: false.
	self
		errorMessage: aByteArrayOrString
		errorCode: anInteger
		domainString: self class subProcessDomain
]

{ #category : #'private - spawning' }
SPSProcess >> handleSpawnSuccess: aProcessToken parentStdout: parentStdout parentStderr: parentStderr [

	self isSpawnSuccess: true.
	processHandle := SPSProcessHandle value: aProcessToken.
	self ffiLibrary fdSetNonBlocking: parentStdout.
	self ffiLibrary fdSetNonBlocking: parentStderr.
	self stdOut: (self readToEndFromFd: parentStdout).
	self stdErr: (self readToEndFromFd: parentStderr).
	parentStdout ifNotNil: [ self ffiLibrary closeFd: parentStdout ].
	parentStderr ifNotNil: [ self ffiLibrary closeFd: parentStderr ].
	processHandle waitForExit
]

{ #category : #private }
SPSProcess >> readToEndFromFd: aFd [

	"Read a non-blocking pipe descriptor until EOF (the child has closed its
	 end, i.e. exited), collecting the raw bytes. A negative read result means
	 no data is currently available, so we briefly yield and retry; EOF (0)
	 stops the loop. Returns a ByteArray."

	| library chunk output done count |
	library := self ffiLibrary.
	chunk := self newOutputReadBuffer.
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
