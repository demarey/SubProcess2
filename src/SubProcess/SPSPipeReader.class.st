"
I model a single readable pipe end of a spawned child process. Raw bytes are
fed to me (by the completion watcher) and I split them into lines, which I:
- buffer so they are available through #readLine (used by #stdOutChannel and
  #stdErrChannel),
- append (plus a line separator) to a collector WriteStream when output
  auto-collection is enabled,
- forward to an #outputLineDo: subscriber when present.

I own the underlying file descriptor and close it when I am released.
"
Class {
	#name : #SPSPipeReader,
	#superclass : #Object,
	#instVars : [
		'fd',
		'encoding',
		'pendingLines',
		'rawTail',
		'collector',
		'outputLineBlock',
		'isEof'
	],
	#category : #SubProcess
}

{ #category : #'instance creation' }
SPSPipeReader class >> fd: anInteger encoding: anEncoding collector: aCollectorOrNil outputLineBlock: aBlockOrNil [

	^ self new
		initializeFd: anInteger
		encoding: anEncoding
		collector: aCollectorOrNil
		outputLineBlock: aBlockOrNil
]

{ #category : #feeding }
SPSPipeReader >> addBytes: aByteArray [

	rawTail := rawTail , aByteArray.
	self extractPendingLines
]

{ #category : #feeding }
SPSPipeReader >> announceEof [

	"Flush any trailing partial line (no final terminator) and mark EOF."

	self isEof ifTrue: [ ^ self ].
	rawTail ifNotEmpty: [ self handleLine: rawTail. rawTail := ByteArray new: 0 ].
	isEof := true
]

{ #category : #'private - line handling' }
SPSPipeReader >> extractPendingLines [

	| index lineBytes |
	[ (index := rawTail indexOf: 10) > 0 ] whileTrue: [
		lineBytes := rawTail copyFrom: 1 to: index - 1.
		rawTail := rawTail copyFrom: index + 1 to: rawTail size.
		self handleLine: lineBytes ]
]

{ #category : #'api - accessing' }
SPSPipeReader >> fd [

	^ fd
]

{ #category : #closing }
SPSPipeReader >> close [

	fd ifNotNil: [
		LibC uniqueInstance close: fd.
		fd := nil.
		isEof := true ]
]

{ #category : #'private - line handling' }
SPSPipeReader >> handleLine: aByteArray [

	| line |
	line := aByteArray decodeWith: encoding.
	line := self stripLineTerminators: line.
	pendingLines add: line.
	collector ifNotNil: [ collector nextPutAll: line; cr ].
	outputLineBlock ifNotNil: [ outputLineBlock value: line ]
]

{ #category : #initialization }
SPSPipeReader >> initializeFd: anInteger encoding: anEncoding collector: aCollectorOrNil outputLineBlock: aBlockOrNil [

	super initialize.
	fd := anInteger.
	encoding := anEncoding.
	collector := aCollectorOrNil.
	outputLineBlock := aBlockOrNil.
	pendingLines := OrderedCollection new.
	rawTail := ByteArray new: 0.
	isEof := false
]

{ #category : #'api - testing' }
SPSPipeReader >> isEof [

	^ isEof
]

{ #category : #'api - reading' }
SPSPipeReader >> nextLine [

	"Answer the next available line (without its terminator), waiting briefly
	 if none is buffered yet, or nil when the stream is exhausted."

	[self isEof and: [ pendingLines isEmpty ]] whileFalse: [
		pendingLines ifNotEmpty: [ ^ pendingLines removeFirst ].
		(2 milliSeconds) asDelay wait ].
	^ nil
]

{ #category : #convenience }
SPSPipeReader >> readLine [

	^ self nextLine
]

{ #category : #'private - line handling' }
SPSPipeReader >> stripLineTerminators: aLine [

	| stripped |
	stripped := aLine.
	[ stripped notEmpty and: [ (stripped last = Character cr) or: [ stripped last = Character lf ] ] ]
		whileTrue: [ stripped := stripped allButLast ].
	^ stripped
]
