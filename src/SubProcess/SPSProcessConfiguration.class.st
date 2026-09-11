"
I represent a Process configuration.
You can configure:
- the encoding to decode process outputs
- the working directory
- the command itself
- and the command arguments
"
Class {
	#name : #SPSProcessConfiguration,
	#superclass : #Object,
	#instVars : [
		'command',
		'arguments',
		'workingDirectory',
		'encoding',
		'collectsOutput',
		'stdInStrategy',
		'stdOutStrategy',
		'stdErrStrategy'
	],
	#category : #SubProcess
}

{ #category : #examples }
SPSProcessConfiguration class >> example [

	(self new
		command: '/bin/ls';
		sync) run
]

{ #category : #'api - configuring' }
SPSProcessConfiguration >> addArgument: aString [ 
	
	arguments 
		ifNil: [ arguments := OrderedCollection with: aString ]
		ifNotNil: [ arguments add: aString ]
]

{ #category : #'api - configuring' }
SPSProcessConfiguration >> addArguments: aCollection [ 
	
	arguments 
		ifNil: [ arguments := OrderedCollection withAll: aCollection ]
		ifNotNil: [ arguments addAll: aCollection ]
]

{ #category : #'api - accessing' }
SPSProcessConfiguration >> arguments [

	^ arguments ifNil: [ #() ]
]

{ #category : #'api - configuring' }
SPSProcessConfiguration >> arguments: aCollection [ 
	
	arguments := aCollection
]

{ #category : #'api - running' }
SPSProcessConfiguration >> async [

	^  SPSAsyncProcess withConfiguration: self
]

{ #category : #'api - configuring' }
SPSProcessConfiguration >> collectsOutput [

	"Enable asynchroneous output auto-collection. Off by default (see shouldCollectOutput)."

	collectsOutput := true
]

{ #category : #'api - accessing' }
SPSProcessConfiguration >> shouldCollectOutput [

	"Answer whether asynchroneous processes built from this configuration should auto-collect
	 their output (stdOut/stdErr). Default is false: output is not captured unless #collectsOutput."

	^ collectsOutput ifNil: [ false ]
]

{ #category : #'api - accessing' }
SPSProcessConfiguration >> command [

	^ command
]{ #category : #'api - configuring' }
SPSProcessConfiguration >> command: aString [ 
	
	command := aString
]

{ #category : #'api - accessing' }
SPSProcessConfiguration >> encoding [ 

	^ encoding
]

{ #category : #'api - configuring' }
SPSProcessConfiguration >> encoding: anEncoding [
	"anEncoding will be used to decode the received Strings, using a specified encoding.
	anEncoding is either a ZnCharacterEncoder instance or an identifier for one."

	encoding := anEncoding
]

{ #category : #'api - configuring' }
SPSProcessConfiguration >> inheritStderr [

	stdErrStrategy := #inherit
]

{ #category : #'api - configuring' }
SPSProcessConfiguration >> inheritStdin [

	stdInStrategy := #inherit
]

{ #category : #'api - configuring' }
SPSProcessConfiguration >> inheritStdout [

	stdOutStrategy := #inherit
]

{ #category : #initialization }
SPSProcessConfiguration >> initialize [

	super initialize.
	"This is just a default encoding. Especially on windows, you could need to set the correct encoding"
	encoding := OSPlatform current isWindows
		ifTrue: [ 'cp-1252' ]
		ifFalse: [ 'utf8' ].
	stdInStrategy := #pipe.
	stdOutStrategy := #pipe.
	stdErrStrategy := #pipe
]

{ #category : #'api - configuring' }
SPSProcessConfiguration >> mergeStandardError [

	self assertStdOutIsPiped.
	stdErrStrategy := #merge
]

{ #category : #'api - configuring' }
SPSProcessConfiguration >> silenceStandardOutput [

	self silenceStdout.
	self silenceStderr
]

{ #category : #'api - configuring' }
SPSProcessConfiguration >> silenceStderr [

	stdErrStrategy := #silence
]

{ #category : #'api - configuring' }
SPSProcessConfiguration >> silenceStdin [

	stdInStrategy := #silence
]

{ #category : #'api - configuring' }
SPSProcessConfiguration >> silenceStdout [

	stdOutStrategy := #silence
]

{ #category : #'api - acquiring' }
SPSProcessConfiguration >> stdErrStrategy [

	^ stdErrStrategy
]

{ #category : #'api - acquiring' }
SPSProcessConfiguration >> stdInStrategy [

	^ stdInStrategy
]

{ #category : #'api - acquiring' }
SPSProcessConfiguration >> stdOutStrategy [

	^ stdOutStrategy
]

{ #category : #private }
SPSProcessConfiguration >> assertStdOutIsPiped [

	"#merge routes stderr onto stdout, which only works when stdout is captured (#pipe)."

	stdOutStrategy = #pipe ifFalse: [
		self error: 'Merging standard error requires standard output to be piped' ]
]

{ #category : #'api - running' }
SPSProcessConfiguration >> sync [

	^  SPSProcess withConfiguration: self
]

{ #category : #'api - configuring' }
SPSProcessConfiguration >> windowsShellCommand [

	command := 'C:\Windows\System32\cmd.exe'.
	arguments 
		ifNil: [ self addArgument: '/C' ]
		ifNotNil: [ arguments addFirst: '/C' ].
]

{ #category : #'api - accessing' }
SPSProcessConfiguration >> workingDirectory [ 

	^ workingDirectory
]

{ #category : #'api - configuring' }
SPSProcessConfiguration >> workingDirectory: aFileReference [ 
	
	workingDirectory := aFileReference.
]
