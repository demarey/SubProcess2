"
I describe and manage the three stdio pipes ($(#stdin)$, $(#stdout)$, $(#stderr)$)
of a spawned child process. I own the whole stdio-pipes lifecycle: creating the
per-stream #SPSPipeEnds through the ffi library, aggregating them, and closing
file descriptors according to the outcome (all ends on failure, or the child
ends plus both stdin ends on success while leaving the parent stdout/stderr ends
open for the success hook).

I hold the ffi library so I can both create and close descriptors myself, but
the per-stream #SPSPipeEnds objects remain pure data.
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
SPSStdioPipes class >> forSpawnUsing: anFfiLibrary [

	"Create the three stdio pipes, answering an SPSStdioPipes or nil if any pipe
	 could not be created. On failure the already created pipes are closed."

	| stdinPipe stdoutPipe stderrPipe |
	stdinPipe := self newPipeUsing: anFfiLibrary kind: self pipeStdinKind.
	stdoutPipe := self newPipeUsing: anFfiLibrary kind: self pipeStdoutKind.
	stderrPipe := self newPipeUsing: anFfiLibrary kind: self pipeStderrKind.
	(stdinPipe isNil or: [ stdoutPipe isNil or: [ stderrPipe isNil ] ])
		ifTrue: [
			(self withStdin: stdinPipe stdout: stdoutPipe stderr: stderrPipe library: anFfiLibrary) closeAll.
			^ nil ].
	^ self withStdin: stdinPipe stdout: stdoutPipe stderr: stderrPipe library: anFfiLibrary
]

{ #category : #constants }
SPSStdioPipes class >> pipeDescriptorBufferSize [

	"Size in bytes of the buffer holding a descriptor (uintptr_t) returned by
	 the spawn shim."

	^ 8
]

{ #category : #constants }
SPSStdioPipes class >> pipeStderrKind [

	"Child-end role value for the stderr pipe, matching the native
	 sps_pipe_kind_t enum."

	^ 2
]

{ #category : #constants }
SPSStdioPipes class >> pipeStdinKind [

	"Child-end role value for the stdin pipe, matching the native
	 sps_pipe_kind_t enum."

	^ 0
]

{ #category : #constants }
SPSStdioPipes class >> pipeStdoutKind [

	"Child-end role value for the stdout pipe, matching the native
	 sps_pipe_kind_t enum."

	^ 1
]

{ #category : #'instance creation' }
SPSStdioPipes class >> withStdin: aStdinPipe stdout: aStdoutPipe stderr: aStderrPipe library: anFfiLibrary [

	^ self new
		initializeStdin: aStdinPipe
		stdout: aStdoutPipe
		stderr: aStderrPipe
		library: anFfiLibrary
]

{ #category : #'private - creation' }
SPSStdioPipes class >> newPipeUsing: anFfiLibrary kind: anInteger [

	"Create an anonymous pipe whose child end is wired for the given kind
	 (#pipeStdinKind, #pipeStdoutKind or #pipeStderrKind) and answer an
	 SPSPipeEnds holding the parent and child fds, or nil if the pipe cannot be
	 created."

	^ self withPipeBuffers: [ :parentBuffer :childBuffer |
		(anFfiLibrary newPipe: anInteger parent: parentBuffer child: childBuffer) = 0
			ifTrue: [ self pipeEndsFromParentBuffer: parentBuffer childBuffer: childBuffer ]
			ifFalse: [ nil ] ]
]

{ #category : #'private - creation' }
SPSStdioPipes class >> withPipeBuffers: aBlock [

	"Run aBlock with two allocated descriptor buffers (parent and child),
	 freeing them afterwards regardless of the answer."

	| parentBuffer childBuffer |
	parentBuffer := self newDescriptorBuffer.
	childBuffer := self newDescriptorBuffer.
	^ [ aBlock value: parentBuffer value: childBuffer ]
		ensure: [ parentBuffer free. childBuffer free ]
]

{ #category : #'private - creation' }
SPSStdioPipes class >> pipeEndsFromParentBuffer: aParentBuffer childBuffer: aChildBuffer [

	"Answer the SPSPipeEnds described by the descriptors stored in the buffers."

	^ SPSPipeEnds
		parent: (self descriptorFrom: aParentBuffer)
		child: (self descriptorFrom: aChildBuffer)
]

{ #category : #'private - creation' }
SPSStdioPipes class >> newDescriptorBuffer [

	"Answer an allocated buffer large enough to hold one descriptor."

	^ ExternalAddress allocate: self pipeDescriptorBufferSize
]

{ #category : #'private - creation' }
SPSStdioPipes class >> descriptorFrom: anAddress [

	"Answer the descriptor (uintptr_t) written by the spawn shim into anAddress."

	^ anAddress unsignedLongLongAt: 1
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

	"Close every descriptor of every pipe. Used when the spawn failed. Pipe
	 ends that were never created (nil) are skipped."

	self closePipeEnds: stdin.
	self closePipeEnds: stdout.
	self closePipeEnds: stderr.
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

{ #category : #'private - closing' }
SPSStdioPipes >> closePipeEnds: aPipeEndsOrNil [

	aPipeEndsOrNil ifNotNil: [
		self closeFd: aPipeEndsOrNil parent.
		self closeFd: aPipeEndsOrNil child ]
]
