"
I model a single writable pipe end used to send input to a spawned child
process (#stdInChannel). I write bytes to the underlying file descriptor.
"
Class {
	#name : #SPSPipeWriter,
	#superclass : #Object,
	#instVars : [
		'fd'
	],
	#category : #SubProcess
}

{ #category : #'instance creation' }
SPSPipeWriter class >> fd: anInteger [

	^ self new initializeFd: anInteger
]

{ #category : #closing }
SPSPipeWriter >> close [

	fd
		ifNotNil: [ (LibC uniqueInstance close: fd). fd := nil ]
]

{ #category : #initialization }
SPSPipeWriter >> initializeFd: anInteger [

	super initialize.
	fd := anInteger
]

{ #category : #writing }
SPSPipeWriter >> nextPutAll: aString [

	| bytes written |
	bytes := aString asByteArray.
	written := LibC uniqueInstance write: fd buffer: bytes size: bytes size.
	^ written
]
