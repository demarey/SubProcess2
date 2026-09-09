"
I record descriptors closed via #closeFd: so unit tests can assert on the
closing policy of SPSStdioPipes without touching the real FFI layer.
"
Class {
	#name : #SPSMockSpawnLibrary,
	#superclass : #Object,
	#instVars : [
		'closedFds'
	],
	#category : #'SubProcess-Tests'
}

{ #category : #initialization }
SPSMockSpawnLibrary >> initialize [

	super initialize.
	closedFds := OrderedCollection new.
]

{ #category : #accessing }
SPSMockSpawnLibrary >> closedFds [

	^ closedFds asArray
]

{ #category : #api }
SPSMockSpawnLibrary >> closeFd: anInteger [

	anInteger ifNotNil: [ closedFds add: anInteger ]
]
