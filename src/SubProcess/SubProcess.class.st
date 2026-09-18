"
I am the abstract root of the subprocess hierarchy. I gather the common
behaviour for synchroneous and asynchroneous child OS process spawn, and I act
as the public entry point: `SubProcess run: '...'` builds a configuration and
runs it synchroneously.

My concrete subclasses are SPSSyncProcess and SPSAsyncProcess.

I use `SPSProcessConfiguration` to configure myself.
"
Class {
	#name : #SubProcess,
	#superclass : #Object,
	#traits : 'SPSTLibrary',
	#classTraits : 'SPSTLibrary classTrait',
	#instVars : [
		'configuration',
		'isComplete',
		'processHandle'
	],
	#category : #SubProcess
}

{ #category : #constants }
SubProcess class >> subProcessDomain [

	"Domain string attached to SPSError instances raised by this package."

	^ 'SubProcess'
]

{ #category : #constants }
SubProcess class >> nullByte [

	"The byte value terminating a C string."

	^ Character null asciiValue
]

{ #category : #constants }
SubProcess class >> spawnErrorBufferSize [

	"Size in bytes of the buffer receiving a NUL-terminated error message when
	 a child fails to spawn."

	^ 1024
]

{ #category : #constants }
SubProcess class >> outputReadBufferSize [

	"Size in bytes read from a child pipe descriptor in a single read call."

	^ 65536
]

{ #category : #'instance creation' }
SubProcess class >> withConfiguration: aSPSProcessConfiguration [

	^ self new
		configuration: aSPSProcessConfiguration
]

{ #category : #'api - running' }
SubProcess class >> run: aCommand [

	^ self
		runProcessForConfiguration: (SPSProcessConfiguration new command: aCommand)
]

{ #category : #'api - running' }
SubProcess class >> run: aCommand arguments: aCollection [

	^ self
		runProcessForConfiguration: (SPSProcessConfiguration new
			command: aCommand;
			arguments: aCollection)
]

{ #category : #'api - running' }
SubProcess class >> start: aCommand [

	^ self
		startProcessForConfiguration: (SPSProcessConfiguration new command: aCommand)
]

{ #category : #'api - running' }
SubProcess class >> start: aCommand arguments: aCollection [

	^ self
		startProcessForConfiguration: (SPSProcessConfiguration new
			command: aCommand;
			arguments: aCollection)
]

{ #category : #'private - running' }
SubProcess class >> runProcessForConfiguration: aSPSProcessConfiguration [

	| process |
	process := aSPSProcessConfiguration asSyncProcess.
	process run.
	^ process
]

{ #category : #'private - running' }
SubProcess class >> startProcessForConfiguration: aSPSProcessConfiguration [

	"Spawn the process described by aSPSProcessConfiguration asynchronously and
	 return it running. Output collection is enabled by default so stdout/stderr
	 are available after #wait / #waitFor:."

	aSPSProcessConfiguration collectsOutput.
	^ aSPSProcessConfiguration asAsyncProcess start
]

{ #category : #'api - accessing' }
SubProcess >> configuration [

	^ configuration
]

{ #category : #'api - configuring' }
SubProcess >> configuration: aSPSProcessConfiguration [ 
	
	configuration := aSPSProcessConfiguration
]

{ #category : #'api - accessing' }
SubProcess >> exitCode [

	self subclassResponsibility
]

{ #category : #initialization }
SubProcess >> initialize [

	super initialize.
	isComplete := false.
]

{ #category : #'api - testing' }
SubProcess >> isComplete [
	
	"True if spawned child program has completed its execution, whatever the reason.
	 Once true, the child program is not running anymore: it either exited by itself
	 (normal or signal exit) or was terminated by the user (see SPSAsyncProcess >> wasTerminated)."
	
	^ isComplete 
]

{ #category : #'api - testing' }
SubProcess >> isExitSuccess [
	
	"True if the child process has completed with a success exit status (exit code 0)."
	
	^ self isComplete and: [ self exitCode = 0 ]
]

{ #category : #'api - testing' }
SubProcess >> isSpawnSuccess [
	
	"True if the child process was spawned/launched without error."
	self subclassResponsibility
]

{ #category : #'private - spawning' }
SubProcess >> isSpawnFailure: aSpawnResult [

	"spawn answers the process token on success and a negated error number on
	 failure, so any value at or below zero denotes a failed spawn."

	^ aSpawnResult <= 0
]

{ #category : #'api - running' }
SubProcess >> run [
	
	self subclassResponsibility
]

{ #category : #'api - running' }
SubProcess >> terminate [
	
	self subclassResponsibility
]

{ #category : #private }
SubProcess >> argsBlob [

	"Answer the command and its arguments as a single NUL-separated blob
	 (see SPSSpawnLibrary), matching the argv expected by the native shim."

	| stream |
	stream := ByteArray new writeStream.
	self appendArgument: self configuration command to: stream.
	self configuration arguments
		do: [ :aString | self appendArgument: aString to: stream ].
	^ stream contents
]

{ #category : #private }
SubProcess >> appendArgument: aString to: stream [

	| separator |
	separator := Character null asciiValue.
	stream nextPutAll: (aString encodeWith: self configuration encoding).
	stream nextPut: separator
]

{ #category : #private }
SubProcess >> cStringBytesFrom: aByteArray [

	"Answer the bytes of a NUL-terminated C string stored in aByteArray, up to
	 but excluding the first NUL."

	| index |
	index := aByteArray indexOf: self class nullByte.
	index = 0 ifTrue: [ ^ ByteArray new: 0 ].
	^ aByteArray first: index - 1
]

{ #category : #private }
SubProcess >> decode: aByteArrayOrString [

	"Decode raw bytes produced by a child process into a Pharo String using the
	 configured encoding. Strings are returned untouched."

	^ aByteArrayOrString isString
		ifTrue: [ aByteArrayOrString ]
		ifFalse: [ aByteArrayOrString decodeWith: self configuration encoding ]
]

{ #category : #private }
SubProcess >> newOutputReadBuffer [

	"Answer a fresh byte buffer used for a single read of a child pipe."

	^ ByteArray new: self class outputReadBufferSize
]

{ #category : #'private - spawning' }
SubProcess >> spawnProcess [

	"Template method that pipes and spawns a child OS process. It creates the
	 three stdio pipes, invokes the native spawn shim and dispatches to the
	 subclass hooks on failure or success.

	 Ownership: SPSStdioPipes closes the child ends and the parent stdin end,
	 and all ends on failure. parentStdout and parentStderr are handed open to
	 the hook, which owns closing them (sync reads then closes, async keeps
	 them as channels)."

	| pipes argsBlob cwd errBuf spawnResult |
	pipes := SPSStdioPipes forSpawnUsing: self ffiLibrary configuration: self configuration.
	pipes ifNil: [ ^ self handleSpawnError: 'Cannot create pipes' code: 0 ].

	argsBlob := self argsBlob.
	cwd := self configuration workingDirectory ifNotNil: [ :file | file fullName ].
	errBuf := ByteArray new: self class spawnErrorBufferSize.
	spawnResult := self
		invokeSpawnWithPipes: pipes
		args: argsBlob
		cwd: cwd
		errBuf: errBuf.

	(self isSpawnFailure: spawnResult)
		ifTrue: [
			pipes closeAll.
			^ self handleSpawnError: (self cStringBytesFrom: errBuf) code: (0 - spawnResult) ].

	pipes closeAfterSuccessfulSpawn.
	^ self
		handleSpawnSuccess: spawnResult
		parentStdout: (self parentEndOf: pipes stdout)
		parentStderr: (self parentEndOf: pipes stderr)
]

{ #category : #'private - spawning' }
SubProcess >> parentEndOf: aPipeEndsOrNil [

	"Answer the parent descriptor of aPipeEndsOrNil, or nil when there is no
	 pipe for that stream (silence / inherit / merge)."

	^ aPipeEndsOrNil ifNotNil: [ aPipeEndsOrNil parent ]
]

{ #category : #'private - spawning' }
SubProcess >> invokeSpawnWithPipes: pipes args: argsBlob cwd: cwd errBuf: errBuf [

	"Invoke the native spawn shim with the stdio spec answered by SPSStdioPipes."

	^ self ffiLibrary
		spawnStdio: pipes stdioSpec
		args: argsBlob
		argsLength: argsBlob byteSize
		cwd: cwd
		error: errBuf
		errorLength: errBuf size
]

{ #category : #'private - spawning' }
SubProcess >> handleSpawnError: aByteArrayOrString code: anInteger [

	self subclassResponsibility
]

{ #category : #'private - spawning' }
SubProcess >> handleSpawnSuccess: aProcessToken parentStdout: aProcessParentStdout parentStderr: aProcessParentStderr [

	"Template method: wire the process handle and make the parent stdout/stderr
	 descriptors non-blocking (when present; silenced / inherited / merged
	 streams have no parent end), then delegate the subclass-specific follow-up
	 (sync drains and waits, async builds the pipe readers)."

	processHandle := SPSProcessHandle value: aProcessToken.
	aProcessParentStdout ifNotNil: [ self ffiLibrary fdSetNonBlocking: aProcessParentStdout ].
	aProcessParentStderr ifNotNil: [ self ffiLibrary fdSetNonBlocking: aProcessParentStderr ].
	^ self processSpawnedWithParentStdout: aProcessParentStdout parentStderr: aProcessParentStderr
]

{ #category : #'private - spawning' }
SubProcess >> processSpawnedWithParentStdout: parentStdout parentStderr: parentStderr [

	self subclassResponsibility
]
