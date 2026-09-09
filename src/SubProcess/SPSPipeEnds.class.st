"
I describe the two file-descriptor ends of one end of a pipe as created by the
native shim: the parent-process fd and the child-process fd. I replace a raw
{ parentFd. childFd } array with named accessors so call sites are self
documenting.
"
Class {
	#name : #SPSPipeEnds,
	#superclass : #Object,
	#instVars : [
		'parentFd',
		'childFd'
	],
	#category : #SubProcess
}

{ #category : #'instance creation' }
SPSPipeEnds class >> parent: aParentFd child: aChildFd [

	^ self new
		initializeParent: aParentFd
		child: aChildFd
]

{ #category : #accessing }
SPSPipeEnds >> child [

	^ childFd
]

{ #category : #initialization }
SPSPipeEnds >> initializeParent: aParentFd child: aChildFd [

	parentFd := aParentFd.
	childFd := aChildFd.
	^ self
]

{ #category : #accessing }
SPSPipeEnds >> parent [

	^ parentFd
]
