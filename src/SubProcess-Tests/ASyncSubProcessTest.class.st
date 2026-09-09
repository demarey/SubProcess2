Class {
	#name : #ASyncSubProcessTest,
	#superclass : #SPSProcessTestCase,
	#category : #'SubProcess-Tests'
}

{ #category : #constants }
ASyncSubProcessTest class >> completionTimeout [

	"Timeout within which a long-running process is expected to still be
	 running, used by the timeout test."

	^ 1 second
]

{ #category : #constants }
ASyncSubProcessTest class >> completionWaitTime [

	"Timeout within which a spawned process must reach completion."

	^ 10 seconds
]

{ #category : #constants }
ASyncSubProcessTest class >> largeOutputLineCount [

	"Number of lines emitted by the large-output test."

	^ 50000
]

{ #category : #constants }
ASyncSubProcessTest class >> longRunningDuration [

	"Duration in seconds a spawned long-running process stays alive before
	 being terminated."

	^ 30 seconds
]

{ #category : #constants }
ASyncSubProcessTest class >> noNewlinePayloadBytes [

	"Number of bytes emitted (without line feed) by the no-newline test."

	^ 200000
]

{ #category : #constants }
ASyncSubProcessTest class >> streamingLineCount [

	"Number of lines emitted by the streaming-output test."

	^ 10
]

{ #category : #constants }
ASyncSubProcessTest class >> streamingWaitTime [

	"Delay allowed for the streaming-output callback lines to arrive."

	^ 5 seconds
]

{ #category : #constants }
ASyncSubProcessTest class >> successExitCode [

	"Exit code asserted on successful process completion."

	^ 0
]

{ #category : #'helpers - building' }
ASyncSubProcessTest >> newProcessConfigurationForDirectoryListing [

	"Answer a configuration producing a non-empty directory listing."

	self isRunningOnWindows
		ifTrue: [ ^ self newProcessConfigurationWithShellCommand: 'dir' ].
	^ SPSProcessConfiguration new
		command: '/bin/ls';
		arguments: #();
		yourself
]

{ #category : #'helpers - building' }
ASyncSubProcessTest >> newProcessConfigurationForLongRunningProcess [

	"Answer a configuration for a process that stays alive for a long time."

	self isRunningOnWindows
		ifTrue: [ ^ self newProcessConfigurationWithShellCommand: ('powershell -Command "Start-Sleep -Seconds {1}"' format: { self class longRunningDuration asSeconds }) ].
	^ SPSProcessConfiguration new
		command: '/bin/sleep';
		arguments: { self class longRunningDuration asSeconds asString };
		yourself
]

{ #category : #'helpers - building' }
ASyncSubProcessTest >> newProcessConfigurationProducingLines: anInteger [

	"Answer a configuration emitting exactly anInteger lines of output."

	self isRunningOnWindows
		ifTrue: [ ^ self newProcessConfigurationWithShellCommand: ('for /L %i in (1,1,{1}) do @echo %i' format: { anInteger }) ].
	^ self newProcessConfigurationWithShellCommand: ('seq 1 {1}' format: { anInteger })
]

{ #category : #'helpers - building' }
ASyncSubProcessTest >> newProcessConfigurationWritingBytesWithoutNewlines: anInteger [

	"Answer a configuration emitting anInteger bytes on stdout with no line
	 feed, using a byte value that survives every platform text-mode pipe
	 (here 'a', 0x61)."

	self isRunningOnWindows
		ifTrue: [ ^ self newProcessConfigurationWithShellCommand: ('powershell -Command "Write-Output -NoNewline (''a'' * {1})"' format: { anInteger }) ].
	^ self newProcessConfigurationWithShellCommand:
		('head -c {1} /dev/zero | tr ''\\0'' ''a''' format: { anInteger })
]

{ #category : #'helpers - waiting' }
ASyncSubProcessTest >> waitForCompletionOf: anAsyncProcess [

	^ self waitFor: [ anAsyncProcess isComplete ] within: self class completionWaitTime
]

{ #category : #tests }
ASyncSubProcessTest >> testAutoCollectedOutput [
	| out |

	process := (self newProcessConfigurationWithShellCommand: 'echo hello')
		collectsOutput;
		async.
	
	process run.
	
	self assert: (self waitForCompletionOf: process).
	self assert: process isComplete.
	self assert: process isExitSuccess.
	out := process stdOut.
	self assert: (out includesSubstring: 'hello').
]

{ #category : #tests }
ASyncSubProcessTest >> testAutoCollectedLargeOutput [
	| out |

	self skipIfRunningOnWindows.
	process := (self newProcessConfigurationWithShellCommand: ('seq 1 {1}' format: { self class largeOutputLineCount }))
		collectsOutput;
		async.

	process run.

	self assert: (self waitForCompletionOf: process).
	self assert: process isComplete.
	self assert: process isExitSuccess.
	out := process stdOut.
	self assert: (out occurrencesOf: Character cr) >= self class largeOutputLineCount.
	self assert: (out includesSubstring: self class largeOutputLineCount asString).
]

{ #category : #tests }
ASyncSubProcessTest >> testCompletion [
	
	process := (self newProcessConfigurationWithShellCommand: ('exit {1}' format: { self class nonZeroExitCode })) async.
	
	process run.
	
	self assert: (self waitForCompletionOf: process).
	self assert: process isComplete.
	self assert: process exitCode equals: self class nonZeroExitCode.
	self deny: process isExitSuccess.
]

{ #category : #tests }
ASyncSubProcessTest >> testCompletionCallback [
	| completed exit |
	
	completed := false.
	exit := nil.
	process := (self newProcessConfigurationWithShellCommand: ('exit {1}' format: { self class successExitCode })) async.
	process whenCompletedDo: [ :aProcess |
		completed := true.
		exit := aProcess exitCode ].
	
	process run.
	
	self assert: (self waitForCompletionOf: process).
	self assert: completed.
	self assert: exit equals: self class successExitCode.
]

{ #category : #tests }
ASyncSubProcessTest >> testOutputWithoutNewlinesLargerThanReadBuffer [

	"Emit more bytes than the pipe read buffer with no line feed; the chunked
	 reads must be re-assembled into a single raw buffer."

	| out payloadBytes |
	payloadBytes := self class noNewlinePayloadBytes.
	self skipIfRunningOnWindows.
	process := (self newProcessConfigurationWritingBytesWithoutNewlines: payloadBytes)
		collectsOutput;
		async.

	process run.

	self assert: (self waitForCompletionOf: process).
	self assert: process isComplete.
	self assert: process isExitSuccess.
	out := process stdOut.
	self assert: out size equals: payloadBytes + 1.    "payload 'a's + the collector's trailing cr"
	self assert: (out occurrencesOf: $a) equals: payloadBytes.
	self assert: (out occurrencesOf: Character cr) equals: 1.
	self deny: (out includes: Character lf).
]

{ #category : #tests }
ASyncSubProcessTest >> testRunningBasicCommand [
	| out |
	
	process := self newProcessConfigurationForDirectoryListing async.
	
	process run.
	
	out := process stdOutChannel readLine.
	self deny: out isEmpty.

]

{ #category : #tests }
ASyncSubProcessTest >> testStreamingOutputCallback [
	| lines |

	lines := OrderedCollection new.
	process := (self newProcessConfigurationProducingLines: self class streamingLineCount) async.
	process outputLineDo: [ :aLine | lines add: aLine ].

	process run.

	self assert: (self waitForCompletionOf: process).
	self assert: (self waitFor: [ lines size >= self class streamingLineCount ] within: self class streamingWaitTime).
	self assert: (lines includes: self class streamingLineCount asString).
]

{ #category : #tests }
ASyncSubProcessTest >> testTerminate [

	process := self newProcessConfigurationForLongRunningProcess async.
	
	process run.
	self deny: process isComplete.
	process terminate.
	
	self assert: process isComplete.
	self assert: process wasTerminated.
]

{ #category : #tests }
ASyncSubProcessTest >> testTimeOut [

	process := self newProcessConfigurationForLongRunningProcess async.
	
	self assert: (process runAndWaitTimeOut: self class completionTimeout).
	self assert: process isComplete.
	self assert: process wasTerminated.
]

{ #category : #tests }
ASyncSubProcessTest >> testRunningANonExistingCommand [

	"Spawning a non-existing command raises SPSError synchronously from #run
	 (the async spawn failure path signals it rather than setting a flag)."

	self skipIfRunningOnWindows.
	process := self newProcessConfigurationForNonExistingCommand async.

	self
		should: [ process run ]
		raise: SPSError
		withExceptionDo: [ :error |
			self
				assert: (error messageText includesSubstring: 'No such file or directory')
				description: 'Expecting "No such file ..." but got ', error messageText ].

	self deny: process isSpawnSuccess.
	self assert: process exitCode isNil.
]
