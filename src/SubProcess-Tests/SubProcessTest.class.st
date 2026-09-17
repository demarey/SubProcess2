"
I unit test the C-string and byte-decoding helpers of SubProcess, and the public
SubProcess run: facade.
"
Class {
	#name : #SubProcessTest,
	#superclass : #TestCase,
	#instVars : [
		'process'
	],
	#category : #'SubProcess-Tests'
}

{ #category : #running }
SubProcessTest >> setUp [

	super setUp.
	process := SubProcess new.
]

{ #category : #configuring }
SubProcessTest >> isRunningOnWindows [

	^ OSPlatform current isWindows
]

{ #category : #configuring }
SubProcessTest >> skipIfRunningOnWindows [

	self isRunningOnWindows ifTrue: [ self skip: 'skipping unix test' ]
]

{ #category : #tests }
SubProcessTest >> testCStringBytesFromAnswersEmptyByteArrayWhenNoTerminator [

	"Regression test: a buffer with no NUL yielded #() (an Array) which could
	 not be fed to a ByteArray decoder. It must answer an empty ByteArray."

	self assert: (process cStringBytesFrom: (ByteArray new: 0)) equals: (ByteArray new: 0).
	self assert: (process cStringBytesFrom: (ByteArray new: 4)) equals: (ByteArray new: 0).
]

{ #category : #tests }
SubProcessTest >> testCStringBytesFromExcludesTerminator [

	| buffer |
	buffer := #[104 101 108 108 111 0 1 2 3].
	self assert: (process cStringBytesFrom: buffer) equals: #[104 101 108 108 111].
]

{ #category : #tests }
SubProcessTest >> testCStringBytesFromStopsAtFirstTerminator [

	self assert: (process cStringBytesFrom: (ByteArray with: 65 with: 0 with: 66))
		equals: #[65].
]

{ #category : #tests }
SubProcessTest >> testDecodingNonAsciiUtf8 [

	| processWithConfig bytes |
	processWithConfig := SubProcess new
		configuration: (SPSProcessConfiguration new encoding: 'utf8').
	bytes := 'café' encodeWith: 'utf8'.
	self
		assert: (processWithConfig decode: bytes)
		equals: 'café'.
]

{ #category : #tests }
SubProcessTest >> testDecodingNonAsciiWithCp1252 [

	| processWithConfig bytes |
	processWithConfig := SubProcess new
		configuration: (SPSProcessConfiguration new encoding: 'cp-1252').
	bytes := 'café' encodeWith: 'cp-1252'.
	self
		assert: (processWithConfig decode: bytes)
		equals: 'café'.
]

{ #category : #tests }
SubProcessTest >> testRunBasicCommand [

	self skipIfRunningOnWindows.
	process := SubProcess run: '/bin/ls'.

	self assert: process isComplete.
	self assert: process isSpawnSuccess.
	self assert: process isExitSuccess.
	self assert: process stdErr isEmpty.
	self deny: process stdOut isEmpty.
]

{ #category : #tests }
SubProcessTest >> testRunNonExistingCommand [

	self
		should: [ SubProcess run: 'non_exisiting_command' ]
		raise: SPSError.
]

{ #category : #tests }
SubProcessTest >> testRunReturnsSyncProcess [

	| spawned |
	self skipIfRunningOnWindows.
	spawned := SubProcess run: '/bin/echo' arguments: { 'hello' }.

	self assert: spawned class equals: SPSSyncProcess.
	self assert: (spawned isKindOf: SubProcess).
]

{ #category : #tests }
SubProcessTest >> testRunWithArguments [

	self skipIfRunningOnWindows.
	process := SubProcess run: '/bin/sh' arguments: { '-c'. 'echo hello' }.

	self assert: process isExitSuccess.
	self assert: (process stdOut includesSubstring: 'hello').
]
