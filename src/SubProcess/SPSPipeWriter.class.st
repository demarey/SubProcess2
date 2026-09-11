"
I model a single writable pipe end used to send input to a spawned child
process (#stdInChannel). I encode the Strings written to me with a configured
encoding, then write those bytes to the underlying file descriptor.
"
Class {
	#name : #SPSPipeWriter,
	#superclass : #Object,
	#traits : 'SPSTLibrary',
	#classTraits : 'SPSTLibrary classTrait',
	#instVars : [
		'fd',
		'encoding'
	],
	#category : #SubProcess
}

{ #category : #'instance creation' }
SPSPipeWriter class >> fd: anInteger encoding: anEncoding [

	^ self new initializeFd: anInteger encoding: anEncoding
]

{ #category : #closing }
SPSPipeWriter >> close [

	fd
		ifNotNil: [ (self ffiLibrary closeFd: fd). fd := nil ]]

{ #category : #initialization }
SPSPipeWriter >> initializeFd: anInteger encoding: anEncoding [

	super initialize.
	fd := anInteger.
	encoding := anEncoding
]

{ #category : #'private - encoding' }
SPSPipeWriter >> bytesFor: aString [

	"Encode aString into the byte representation used by the configured encoding."

	^ aString encodeWith: encoding
]

{ #category : #writing }
SPSPipeWriter >> nextPutAll: aString [

	| bytes written |
	bytes := self bytesFor: aString.
	written := self ffiLibrary write: fd buffer: bytes size: bytes size.
	^ written
]
