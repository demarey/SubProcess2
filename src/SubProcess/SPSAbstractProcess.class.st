"
Common behaviour for synchroneous and asynchroneous child OS process spawn.
I use `SPSProcessConfiguration` to configure myself.

"
Class {
	#name : #SPSAbstractProcess,
	#superclass : #Object,
	#instVars : [
		'configuration',
		'isComplete'
	],
	#category : #SubProcess
}

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

{ #category : #'ffi - library' }
SPSAbstractProcess >> ffiLibrary [

	^ SPSSpawnLibrary uniqueInstance
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
SPSAbstractProcess >> closeAllPipeFds: aCollection [

	aCollection do: [ :fd | self closeFd: fd ]
]

{ #category : #private }
SPSAbstractProcess >> closeFd: anInteger [

	anInteger
		ifNotNil: [ self ffiLibrary closeFd: anInteger ]
]

{ #category : #private }
SPSAbstractProcess >> newPipeFor: aRole [

	"Create an anonymous pipe whose child end is wired for the given child
	 stream role (#stdin, #stdout or #stderr) and answer an array
	 { parentFd. childFd }, or nil if the pipe cannot be created."

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
				{ parent. child } ]
			ifFalse: [ nil ] ]
		ensure: [ parentBuffer free. childBuffer free ]
]

{ #category : #private }
SPSAbstractProcess >> cStringBytesFrom: aByteArray [

	"Answer the bytes of a NUL-terminated C string stored in aByteArray, up to
	 but excluding the first NUL."

	| index |
	index := aByteArray indexOf: self class nullByte.
	index = 0 ifTrue: [ ^ #() ].
	^ aByteArray first: index - 1
]
