"
I describe the three stdio pipes ($(#stdin)$, $(#stdout)$, $(#stderr)$) of a
spawned child process. I aggregate the per-stream #SPSPipeEnds and own the
file-descriptor closing policy: the whole set on failure, or the child ends
(plus both stdin ends) on success while leaving the parent stdout/stderr ends
open for the success hook.

I hold the ffi library so I can close descriptors myself, but the per-stream
#SPSPipeEnds objects remain pure data.
"
Class {
	#name : #SPSStdioPipes,
	#superclass : #Object,
	#instVars : [
		'stdin',
		'stdout',
		'stderr',
		'library'
	],
	#category : #SubProcess
}

{ #category : #'instance creation' }
SPSStdioPipes class >> stdin: aStdinPipe stdout: aStdoutPipe stderr: aStderrPipe library: anFfiLibrary [

	^ self new
		initializeStdin: aStdinPipe
		stdout: aStdoutPipe
		stderr: aStderrPipe
		library: anFfiLibrary
]

{ #category : #accessing }
SPSStdioPipes >> stderr [

	^ stderr
]

{ #category : #accessing }
SPSStdioPipes >> stdin [

	^ stdin
]

{ #category : #accessing }
SPSStdioPipes >> stdout [

	^ stdout
]

{ #category : #initialization }
SPSStdioPipes >> initializeStdin: aStdinPipe stdout: aStdoutPipe stderr: aStderrPipe library: anFfiLibrary [

	stdin := aStdinPipe.
	stdout := aStdoutPipe.
	stderr := aStderrPipe.
	library := anFfiLibrary.
	^ self
]

{ #category : #'private - closing' }
SPSStdioPipes >> closeFd: anInteger [

	anInteger
		ifNotNil: [ library closeFd: anInteger ]
]

{ #category : #closing }
SPSStdioPipes >> closeAll [

	"Close every descriptor of every pipe. Used when the spawn failed."

	self closeFd: stdin parent.
	self closeFd: stdin child.
	self closeFd: stdout parent.
	self closeFd: stdout child.
	self closeFd: stderr parent.
	self closeFd: stderr child.
]

{ #category : #closing }
SPSStdioPipes >> closeAfterSuccessfulSpawn [

	"Close both stdin ends and the child ends of stdout and stderr. The parent
	 ends of stdout and stderr stay open for the success hook."

	self closeFd: stdin parent.
	self closeFd: stdin child.
	self closeFd: stdout child.
	self closeFd: stderr child.
]
