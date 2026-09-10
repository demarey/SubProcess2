"
I describe the two file-descriptor ends of one pipe as created by the native
shim: the parent-process fd and the child-process fd. A pipe is a byte channel
with a read end and a write end; I bundle the two fds as { parent. child },
replacing a raw array with named accessors so call sites are self documenting.

Within a pipe, the direction of data flow depends on the pipe kind:
- STDIN  : the parent writes and the child reads (parent = write end).
- STDOUT / STDERR : the child writes and the parent reads (parent = read end).

The child end of each pipe is handed to the spawned child (it becomes the
child's fd 0/1/2), while the parent end stays with us to write input (stdin)
or read the child's output (stdout/stderr).
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
