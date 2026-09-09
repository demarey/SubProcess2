"
I model a single writable pipe end used to send input to a spawned child
process (#stdInChannel). I write bytes to the underlying file descriptor.
"
Class {
	#name : #SPSPipeWriter,
	#superclass : #Object,
	#traits : 'SPSTLibrary',
	#classTraits : 'SPSTLibrary classTrait',
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
		ifNotNil: [ (self ffiLibrary closeFd: fd). fd := nil ]]

{ #category : #initialization }
SPSPipeWriter >> initializeFd: anInteger [

	super initialize.
	fd := anInteger
]

{ #category : #writing }
SPSPipeWriter >> nextPutAll: aString [

	| bytes written |
	bytes := aString asByteArray.
	written := self ffiLibrary write: fd buffer: bytes size: bytes size.
	^ written
]
