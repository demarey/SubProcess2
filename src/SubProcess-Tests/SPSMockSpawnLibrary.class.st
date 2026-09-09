"
I record descriptors closed via #closeFd: so unit tests can assert on the
closing policy of SPSStdioPipes without touching the real FFI layer. For
creation tests, #scriptPipeKind:parent:child: queues pipe descriptors that
#newPipe:parent:child: hands back through the buffers in FIFO order.
"
Class {
	#name : #SPSMockSpawnLibrary,
	#superclass : #Object,
	#instVars : [
		'closedFds',
		'createdPipes'
	],
	#category : #'SubProcess-Tests'
}

{ #category : #initialization }
SPSMockSpawnLibrary >> initialize [

	super initialize.
	closedFds := OrderedCollection new.
	createdPipes := OrderedCollection new.
]

{ #category : #accessing }
SPSMockSpawnLibrary >> closedFds [

	^ closedFds asArray
]

{ #category : #accessing }
SPSMockSpawnLibrary >> createdPipes [

	^ createdPipes asArray
]

{ #category : #api }
SPSMockSpawnLibrary >> closeFd: anInteger [

	anInteger ifNotNil: [ closedFds add: anInteger ]
]

{ #category : #api }
SPSMockSpawnLibrary >> newPipe: anInteger parent: aParentBuffer child: aChildBuffer [

	| pair |
	createdPipes ifEmpty: [ ^ 1 ].
	pair := createdPipes removeFirst.
	aParentBuffer unsignedLongLongAt: 1 put: pair second.
	aChildBuffer unsignedLongLongAt: 1 put: pair third.
	^ 0
]

{ #category : #'scripting - pipes' }
SPSMockSpawnLibrary >> scriptPipeKind: anInteger parent: aParentFd child: aChildFd [

	createdPipes add: (Array with: anInteger with: aParentFd with: aChildFd).
	^ self
]
