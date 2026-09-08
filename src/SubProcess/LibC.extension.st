Extension { #name : 'LibC' }

{ #category : '*SubProcess' }
LibC >> createPipe: anExternalAddress [

	"Create an anonymous pipe. On success writes the read and write file
	 descriptors (two int32) into the supplied 8-byte external buffer and
	 answers 0; answers -1 on failure."

	^ self ffiCall: #(int pipe(int* anExternalAddress))
]

{ #category : '*SubProcess' }
LibC >> kill: anIntegerPid signal: anIntegerSignal [

	^ self ffiCall: #(int kill(int anIntegerPid, int anIntegerSignal))
]

{ #category : '*SubProcess' }
LibC >> write: aFileDescriptor buffer: aByteArray size: aCount [

	^ self ffiCall: #(ssize_t write(int aFileDescriptor, void* aByteArray, size_t aCount))
]
