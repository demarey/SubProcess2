"
I unit test the C-string and byte-decoding helpers of SPSAbstractProcess.
"
Class {
	#name : #SPSAbstractProcessTest,
	#superclass : #TestCase,
	#instVars : [
		'process'
	],
	#category : #'SubProcess-Tests'
}

{ #category : #running }
SPSAbstractProcessTest >> setUp [

	super setUp.
	process := SPSAbstractProcess new.
]

{ #category : #tests }
SPSAbstractProcessTest >> testCStringBytesFromAnswersEmptyByteArrayWhenNoTerminator [

	"Regression test: a buffer with no NUL yielded #() (an Array) which could
	 not be fed to a ByteArray decoder. It must answer an empty ByteArray."

	self assert: (process cStringBytesFrom: (ByteArray new: 0)) equals: (ByteArray new: 0).
	self assert: (process cStringBytesFrom: (ByteArray new: 4)) equals: (ByteArray new: 0).
]

{ #category : #tests }
SPSAbstractProcessTest >> testCStringBytesFromExcludesTerminator [

	| buffer |
	buffer := #[104 101 108 108 111 0 1 2 3].
	self assert: (process cStringBytesFrom: buffer) equals: #[104 101 108 108 111].
]

{ #category : #tests }
SPSAbstractProcessTest >> testCStringBytesFromStopsAtFirstTerminator [

	self assert: (process cStringBytesFrom: (ByteArray with: 65 with: 0 with: 66))
		equals: #[65].
]

{ #category : #tests }
SPSAbstractProcessTest >> testDecodingNonAsciiUtf8 [

	| processWithConfig bytes |
	processWithConfig := SPSAbstractProcess new
		configuration: (SPSProcessConfiguration new encoding: 'utf8').
	bytes := 'café' encodeWith: 'utf8'.
	self
		assert: (processWithConfig decode: bytes)
		equals: 'café'.
]

{ #category : #tests }
SPSAbstractProcessTest >> testDecodingNonAsciiWithCp1252 [

	| processWithConfig bytes |
	processWithConfig := SPSAbstractProcess new
		configuration: (SPSProcessConfiguration new encoding: 'cp-1252').
	bytes := 'café' encodeWith: 'cp-1252'.
	self
		assert: (processWithConfig decode: bytes)
		equals: 'café'.
]
