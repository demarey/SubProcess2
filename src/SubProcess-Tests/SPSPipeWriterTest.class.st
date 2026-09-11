"
I unit test the byte encoding performed by SPSPipeWriter when an input String
is prepared for the child's stdin pipe.
"
Class {
	#name : #SPSPipeWriterTest,
	#superclass : #TestCase,
	#category : #'SubProcess-Tests'
}

{ #category : #helpers }
SPSPipeWriterTest >> assert: aString roundTripsThroughEncoding: anEncoding [

	"Bytes produced by SPSPipeWriter for aString must decode back to aString
	 using anEncoding, proving the byte representation matches that encoding."

	| writer bytes |
	writer := SPSPipeWriter fd: 3 encoding: anEncoding.
	bytes := writer bytesFor: aString.
	self assert: (bytes decodeWith: anEncoding) equals: aString
]

{ #category : #tests }
SPSPipeWriterTest >> testBytesForNonAsciiRoundTripsThroughCp1252 [

	self assert: 'café' roundTripsThroughEncoding: 'cp-1252'
]

{ #category : #tests }
SPSPipeWriterTest >> testBytesForNonAsciiRoundTripsThroughUtf8 [

	self assert: 'café' roundTripsThroughEncoding: 'utf8'
]

{ #category : #tests }
SPSPipeWriterTest >> testBytesForAsciiIsUnchanged [

	| writer bytes |
	writer := SPSPipeWriter fd: 3 encoding: 'utf8'.
	bytes := writer bytesFor: 'hello world'.
	self assert: bytes equals: 'hello world' asByteArray.
]
