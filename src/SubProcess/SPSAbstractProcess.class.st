"
Common behaviour for synchroneous and asynchroneous child OS process spawn.
I use `SPSProcessConfiguration` to configure myself.

"
Class {
	#name : #SPSAbstractProcess,
	#superclass : #Object,
	#traits : 'SPSTLibrary',
	#classTraits : 'SPSTLibrary classTrait',
	#instVars : [
		'configuration',
		'isComplete'
	],
	#category : #SubProcess
}

{ #category : #constants }
SPSAbstractProcess class >> subProcessDomain [

	"Domain string attached to SPSError instances raised by this package."

	^ 'SubProcess'
]

{ #category : #constants }
SPSAbstractProcess class >> nullByte [

	"The byte value terminating a C string."

	^ Character null asciiValue
]

{ #category : #constants }
SPSAbstractProcess class >> spawnErrorBufferSize [

	"Size in bytes of the buffer receiving a NUL-terminated error message when
	 a child fails to spawn."

	^ 1024
]

{ #category : #constants }
SPSAbstractProcess class >> outputReadBufferSize [

	"Size in bytes read from a child pipe descriptor in a single read call."

	^ 65536
]

{ #category : #constants }
SPSAbstractProcess class >> pipeDescriptorBufferSize [

	"Size in bytes of the buffer holding a descriptor (uintptr_t) returned by
	 the spawn shim."

	^ 8
]

{ #category : #constants }
SPSAbstractProcess class >> pipeStderrKind [

	"Child-end role value for the stderr pipe, matching the native
	 sps_pipe_kind_t enum."

	^ 2
]

{ #category : #constants }
SPSAbstractProcess class >> pipeStdinKind [

	"Child-end role value for the stdin pipe, matching the native
	 sps_pipe_kind_t enum."

	^ 0
]

{ #category : #constants }
SPSAbstractProcess class >> pipeStdoutKind [

	"Child-end role value for the stdout pipe, matching the native
	 sps_pipe_kind_t enum."

	^ 1
]

{ #category : #'instance creation' }
SPSAbstractProcess class >> withConfiguration: aSPSProcessConfiguration [

	^ self new
		configuration: aSPSProcessConfiguration
]

{ #category : #'api - accessing' }
SPSAbstractProcess >> configuration [

	^ configuration
]

{ #category : #'api - configuring' }
SPSAbstractProcess >> configuration: aSPSProcessConfiguration [ 
	
	configuration := aSPSProcessConfiguration
]

{ #category : #'api - accessing' }
SPSAbstractProcess >> exitCode [

	self subclassResponsibility
]

{ #category : #initialization }
SPSAbstractProcess >> initialize [

	super initialize.
	isComplete := false.
]

{ #category : #'api - testing' }
SPSAbstractProcess >> isComplete [
	
	"True if spawned child program has completed its execution, whatever the reason.
	 Once true, the child program is not running anymore: it either exited by itself
	 (normal or signal exit) or was terminated by the user (see SPSAsyncProcess >> wasTerminated)."
	
	^ isComplete 
]

{ #category : #'api - testing' }
SPSAbstractProcess >> isExitSuccess [
	
	"True if the child process has completed with a success exit status (exit code 0)."
	
	^ self isComplete and: [ self exitCode = 0 ]
]

{ #category : #'api - testing' }
SPSAbstractProcess >> isSpawnSuccess [
	
	"True if the child process was spawned/launched without error."
	self subclassResponsibility
]

{ #category : #'private - spawning' }
SPSAbstractProcess >> isSpawnFailure: aSpawnResult [

	"spawn answers the process token on success and a negated error number on
	 failure, so any value at or below zero denotes a failed spawn."

	^ aSpawnResult <= 0
]

{ #category : #'api - running' }
SPSAbstractProcess >> run [
	
	self subclassResponsibility
]

{ #category : #'api - running' }
SPSAbstractProcess >> terminate [
	
	self subclassResponsibility
]

{ #category : #private }
SPSAbstractProcess >> argsBlob [

	"Answer the command and its arguments as a single NUL-separated blob
	 (see SPSSpawnLibrary), matching the argv expected by the native shim."

	^ String streamContents: [ :stream |
		| addArgument |
		addArgument := [ :aString | stream nextPutAll: aString; nextPut: Character null ].
		addArgument value: self configuration command.
		self configuration arguments do: addArgument ]
]

{ #category : #private }
SPSAbstractProcess >> newPipeFor: aRole [

	"Create an anonymous pipe whose child end is wired for the given child
	 stream role (#stdin, #stdout or #stderr) and answer an SPSPipeEnds holding
	 the parent and child fds, or nil if the pipe cannot be created."

	| kind parentBuffer childBuffer parent child |
	kind := aRole = #stdin ifTrue: [ self class pipeStdinKind ]
		ifFalse: [ aRole = #stderr ifTrue: [ self class pipeStderrKind ] ifFalse: [ self class pipeStdoutKind ] ].
	parentBuffer := ExternalAddress allocate: self class pipeDescriptorBufferSize.
	childBuffer := ExternalAddress allocate: self class pipeDescriptorBufferSize.
	^ [
		(self ffiLibrary newPipe: kind parent: parentBuffer child: childBuffer) = 0
			ifTrue: [
				parent := parentBuffer unsignedLongLongAt: 1.
				child := childBuffer unsignedLongLongAt: 1.
				SPSPipeEnds parent: parent child: child ]
			ifFalse: [ nil ] ]
		ensure: [ parentBuffer free. childBuffer free ]
]

{ #category : #private }
SPSAbstractProcess >> cStringBytesFrom: aByteArray [

	"Answer the bytes of a NUL-terminated C string stored in aByteArray, up to
	 but excluding the first NUL."

	| index |
	index := aByteArray indexOf: self class nullByte.
	index = 0 ifTrue: [ ^ ByteArray new: 0 ].
	^ aByteArray first: index - 1
]

{ #category : #private }
SPSAbstractProcess >> decode: aByteArrayOrString [

	"Decode raw bytes produced by a child process into a Pharo String using the
	 configured encoding. Strings are returned untouched."

	^ aByteArrayOrString isString
		ifTrue: [ aByteArrayOrString ]
		ifFalse: [ aByteArrayOrString decodeWith: self configuration encoding ]
]

{ #category : #private }
SPSAbstractProcess >> newOutputReadBuffer [

	"Answer a fresh byte buffer used for a single read of a child pipe."

	^ ByteArray new: self class outputReadBufferSize
]

{ #category : #private }
SPSAbstractProcess >> createStdioPipes [

	"Create the three stdio pipes as an SPSStdioPipes, or nil if any pipe could
	 not be created. On failure the already created pipes are closed before
	 answering nil."

	| stdinPipe stdoutPipe stderrPipe |
	stdinPipe := self newPipeFor: #stdin.
	stdoutPipe := self newPipeFor: #stdout.
	stderrPipe := self newPipeFor: #stderr.
	(stdinPipe isNil or: [ stdoutPipe isNil or: [ stderrPipe isNil ] ])
		ifTrue: [
			(SPSStdioPipes stdin: stdinPipe stdout: stdoutPipe stderr: stderrPipe library: self ffiLibrary) closeAll.
			^ nil ].
	^ SPSStdioPipes stdin: stdinPipe stdout: stdoutPipe stderr: stderrPipe library: self ffiLibrary
]

{ #category : #'private - spawning' }
SPSAbstractProcess >> spawnProcess [

	"Template method that pipes and spawns a child OS process. It creates the
	 three stdio pipes, invokes the native spawn shim and dispatches to the
	 subclass hooks on failure or success.

	 Ownership: SPSStdioPipes closes the child ends and the parent stdin end,
	 and all ends on failure. parentStdout and parentStderr are handed open to
	 the hook, which owns closing them (sync reads then closes, async keeps
	 them as channels)."

	| pipes argsBlob cwd errBuf spawnResult |
	pipes := self createStdioPipes.
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
	^ self handleSpawnSuccess: spawnResult parentStdout: pipes stdout parent parentStderr: pipes stderr parent
]

{ #category : #'private - spawning' }
SPSAbstractProcess >> invokeSpawnWithPipes: pipes args: argsBlob cwd: cwd errBuf: errBuf [

	"Invoke the native spawn shim with the file descriptors of the stdio pipes
	 answered by #createStdioPipes."

	^ self ffiLibrary
		spawnStdin: pipes stdin child
		stdout: pipes stdout child
		stderr: pipes stderr child
		args: argsBlob
		argsLength: argsBlob byteSize
		cwd: cwd
		error: errBuf
		errorLength: errBuf size
]

{ #category : #'private - spawning' }
SPSAbstractProcess >> handleSpawnError: aByteArrayOrString code: anInteger [

	self subclassResponsibility
]

{ #category : #'private - spawning' }
SPSAbstractProcess >> handleSpawnSuccess: aProcessToken parentStdout: parentStdout parentStderr: parentStderr [

	self subclassResponsibility
]
