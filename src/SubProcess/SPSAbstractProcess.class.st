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
		ifNotNil: [ SPSSpawnLibrary uniqueInstance closeFd: anInteger ]
]

{ #category : #private }
SPSAbstractProcess >> newPipeFor: aRole [

	"Create an anonymous pipe whose child end is wired for the given child
	 stream role (#stdin, #stdout or #stderr) and answer an array
	 { parentFd. childFd }, or nil if the pipe cannot be created."

	| kind parentBuffer childBuffer parent child |
	kind := aRole = #stdin ifTrue: [ 0 ] ifFalse: [ 1 ].
	parentBuffer := ExternalAddress allocate: 8.
	childBuffer := ExternalAddress allocate: 8.
	^ [
		(SPSSpawnLibrary uniqueInstance newPipe: kind parent: parentBuffer child: childBuffer) = 0
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
	index := aByteArray indexOf: 0.
	index = 0 ifTrue: [ ^ #() ].
	^ aByteArray first: index - 1
]

{ #category : #private }
SPSAbstractProcess >> decodeExitCodeFromWaitStatus: anInteger [

	"Decode a child wait status following the POSIX WIFEXITED/WEXITSTATUS
	 rules: a normal exit yields the low 8 bits of the shifted status; any
	 other termination (e.g. killed by a signal) has no simple exit code, so
	 we answer nil (matching GLib's behaviour of reporting no exit code)."

	(anInteger bitAnd: 16r7F) = 0 ifTrue: [ ^ (anInteger bitShift: -8) bitAnd: 16rFF ].
	^ nil
]
