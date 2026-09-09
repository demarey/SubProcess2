"
I allow to spawn child OS processes asynchroneously:
execution resumes immediately after the child process is spawned, without
waiting for its termination. You can provide a callback if you need to do some
actions after the child process is completed.

The process lifecycle is managed in the background by a watcher process that
polls the child with `waitpid(WNOHANG)` (replacing the former GLib child-watch
and main-context iteration) and, while the child runs, drains its standard
output and error pipes, feeding them to SPSPipeReader instances. The readers
stream lines to an `outputLineDo:` subscriber and/or collect them into
`stdOut`/`stdErr` when auto-collection is enabled, and also serve the raw
`stdOutChannel`/`stdErrChannel`. Before completion is announced, the pipes are
drained to EOF so the collected output is complete.

I use `SPSProcessConfiguration` to configure myself.
"
Class {
	#name : #SPSAsyncProcess,
	#superclass : #SPSAbstractProcess,
	#instVars : [
		'processHandle',
		'completionSemaphore',
		'completionBlock',
		'outputLineBlock',
		'stdOutCollector',
		'stdErrCollector',
		'stdOutPipeReader',
		'stdErrPipeReader',
		'stdInWriter',
		'watchWorker',
		'wasTerminated',
		'stopRequested',
		'readBuffer',
		'stdOutFd',
		'stdErrFd'
	],
	#category : #SubProcess
}

{ #category : #'private - lifecycle' }
SPSAsyncProcess >> announceCompleted [

	completionBlock ifNotNil: [ completionBlock value: self ]
]

{ #category : #'private - lifecycle' }
SPSAsyncProcess >> completeWithExitCode: anExitCode [

	self drainOutputToEof.
	completionSemaphore signal.
	isComplete := true.
	self announceCompleted
]

{ #category : #'private - accessing' }
SPSAsyncProcess >> completionSemaphore [

	^ completionSemaphore ifNil: [ completionSemaphore := Semaphore new ]
]

{ #category : #'private - output' }
SPSAsyncProcess >> drainOutputToEof [

	[ self bothChannelsAtEof ] whileFalse: [
		self pumpOutput.
		(1 milliSecond) asDelay wait ]
]

{ #category : #'api - accessing' }
SPSAsyncProcess >> exitCode [

	"Answer the exit code of the child process, or nil if the process has not
	 completed yet or did not exit normally."

	^ processHandle ifNotNil: [ processHandle exitCode ]
]

{ #category : #'api - running' }
SPSAsyncProcess >> run [

	stopRequested := false.
	completionSemaphore := Semaphore new.
	self spawnProcess.
	self watchCompletion
]

{ #category : #'api - running' }
SPSAsyncProcess >> runAndWaitTimeOut: aDuration [

	"Run the process and wait at most aDuration for its completion.
	 Answer true if it timed out, false if it completed within the delay."

	| timedOut |
	self run.
	timedOut := self completionSemaphore waitTimeoutMilliseconds: aDuration asMilliSeconds.
	timedOut ifTrue: [ self terminate ].
	^ timedOut
]

{ #category : #'api - accessing' }
SPSAsyncProcess >> shouldCollectOutput [

	^ self configuration shouldCollectOutput
]

{ #category : #'api - running' }
SPSAsyncProcess >> terminate [

	isComplete ifTrue: [ ^ self ].

	stopRequested := true.
	processHandle ifNotNil: [
		processHandle terminate.
		processHandle waitForExit ].
	self closeOutputChannels.
	wasTerminated := true.
	isComplete := true.
	completionSemaphore signal.
	self announceCompleted
]

{ #category : #'api - testing' }
SPSAsyncProcess >> isSpawnSuccess [

	"True if the child process was spawned/launched without error. Since a spawn
	 failure makes #run raise an error, this answers true as soon as the process
	 exists (after a successful #run)."

	^ processHandle isNotNil
]

{ #category : #'api - testing' }
SPSAsyncProcess >> wasTerminated [

	"True if the child program was killed on user request via #terminate
	 (usually because of a timeout). Answers the reason why the process
	 finished, to be used along with #isComplete:
	 - isComplete = true and wasTerminated = false means the child exited itself,
	 - isComplete = true and wasTerminated = true means it was killed by the caller."

	^ wasTerminated ifNil: [ false ]
]

{ #category : #'api - events' }
SPSAsyncProcess >> whenCompletedDo: aBlock [

	"When the process completes its execution, evaluate aBlock with the process
	 as argument. The process completes only once and supports a single
	 subscriber: a later call replaces the previously registered block."

	completionBlock := aBlock
]

{ #category : #'api - configuring' }
SPSAsyncProcess >> outputLineDo: aBlock [

	"Evaluate aBlock with each output line (stdout and stderr) as it is produced,
	 without buffering the whole output. Useful for processes producing a large
	 amount of output."

	outputLineBlock := aBlock.
	^ self
]

{ #category : #'api - accessing' }
SPSAsyncProcess >> outputLineBlock [

	^ outputLineBlock
]

{ #category : #'api - accessing' }
SPSAsyncProcess >> stdErr [

	^ stdErrCollector ifNil: [ '' ] ifNotNil: [ stdErrCollector contents ]
]

{ #category : #'api - accessing' }
SPSAsyncProcess >> stdErrChannel [

	^ stdErrPipeReader
]

{ #category : #'api - accessing' }
SPSAsyncProcess >> stdInChannel [

	^ stdInWriter ifNil: [ stdInWriter ]
]

{ #category : #'api - accessing' }
SPSAsyncProcess >> stdOut [

	^ stdOutCollector ifNil: [ '' ] ifNotNil: [ stdOutCollector contents ]
]

{ #category : #'api - accessing' }
SPSAsyncProcess >> stdOutChannel [

	^ stdOutPipeReader
]

{ #category : #'private - output' }
SPSAsyncProcess >> pumpOutput [

	self pumpReader: stdOutPipeReader fromFd: stdOutFd.
	self pumpReader: stdErrPipeReader fromFd: stdErrFd
]

{ #category : #'private - output' }
SPSAsyncProcess >> pumpReader: aReader fromFd: aFd [

	| count |
	aReader ifNil: [ ^ self ].
	aReader isEof ifTrue: [ ^ self ].
	count := self ffiLibrary read: aFd buffer: readBuffer size: readBuffer size.
	count > 0
		ifTrue: [ aReader addBytes: (readBuffer first: count) ]
		ifFalse: [ count = 0 ifTrue: [ aReader announceEof ] ]
]

{ #category : #'private - output' }
SPSAsyncProcess >> bothChannelsAtEof [

	^ (stdOutPipeReader isNil or: [ stdOutPipeReader isEof ])
		and: [ stdErrPipeReader isNil or: [ stdErrPipeReader isEof ] ]
]

{ #category : #'private - lifecycle' }
SPSAsyncProcess >> watchCompletion [

	watchWorker := [
		[ stopRequested or: [ processHandle pollForExit ] ] whileFalse: [
			self pumpOutput.
			(3 milliSeconds) asDelay wait ].
		stopRequested ifFalse: [ self completeWithExitCode: processHandle exitCode ] ]
		forkAt: Processor userBackgroundPriority
		named: 'SubProcess-completion-watch'
]

{ #category : #'private - lifecycle' }
SPSAsyncProcess >> spawnProcess [

	| stdinPipe stdoutPipe stderrPipe
	  childStdin childStdout childStderr
	  parentStdin parentStdout parentStderr
	  argsBlob cwd errBuf spawnResult |
	stdinPipe := self newPipeFor: #stdin.
	stdoutPipe := self newPipeFor: #stdout.
	stderrPipe := self newPipeFor: #stderr.
	(stdinPipe isNil or: [ stdoutPipe isNil or: [ stderrPipe isNil ] ])
		ifTrue: [ self signalSpawnError: 'Cannot create pipes' code: 0 ].

	childStdin := stdinPipe second.
	parentStdin := stdinPipe first.
	childStdout := stdoutPipe second.
	parentStdout := stdoutPipe first.
	childStderr := stderrPipe second.
	parentStderr := stderrPipe first.

	argsBlob := self argsBlob.
	cwd := self configuration workingDirectory ifNotNil: [ :file | file fullName ].
	errBuf := ByteArray new: 1024.
	spawnResult := self ffiLibrary
		spawnStdin: childStdin
		stdout: childStdout
		stderr: childStderr
		args: argsBlob
		argsLength: argsBlob byteSize
		cwd: cwd
		error: errBuf
		errorLength: errBuf size.

	spawnResult <= 0
		ifTrue: [
			self closeAllPipeFds: {
				childStdin. parentStdin. childStdout. parentStdout. childStderr. parentStderr }.
			self signalSpawnError: (self cStringBytesFrom: errBuf) code: (0 - spawnResult) ].

	"Child ends and the stdin write end of the parent are closed; the child
	 stdin pipe is not used by this package's readers."
	self closeAllPipeFds: { childStdin. childStdout. childStderr. parentStdin }.
	processHandle := SPSProcessHandle value: spawnResult.
	stdOutFd := parentStdout.
	stdErrFd := parentStderr.
	self ffiLibrary fdSetNonBlocking: stdOutFd.
	self ffiLibrary fdSetNonBlocking: stdErrFd.
	readBuffer := ByteArray new: 65536.
	stdOutPipeReader := SPSPipeReader
		fd: stdOutFd
		encoding: self configuration encoding
		collector: (self configuration shouldCollectOutput ifTrue: [ stdOutCollector := WriteStream on: String new ] ifFalse: [ nil ])
		outputLineBlock: outputLineBlock.
	stdErrPipeReader := SPSPipeReader
		fd: stdErrFd
		encoding: self configuration encoding
		collector: (self configuration shouldCollectOutput ifTrue: [ stdErrCollector := WriteStream on: String new ] ifFalse: [ nil ])
		outputLineBlock: outputLineBlock
]

{ #category : #'private - lifecycle' }
SPSAsyncProcess >> signalSpawnError: aByteArrayOrString code: anInteger [

	| domain |
	domain := 'SubProcess'.
	(SPSError message: ((aByteArrayOrString isByteArray
		ifTrue: [ aByteArrayOrString decodeWith: self configuration encoding ]
		ifFalse: [ aByteArrayOrString ])) code: anInteger domainString: domain) signal
]

{ #category : #'private - output' }
SPSAsyncProcess >> closeOutputChannels [

	stdOutPipeReader ifNotNil: [ stdOutPipeReader close. stdOutPipeReader := nil ].
	stdErrPipeReader ifNotNil: [ stdErrPipeReader close. stdErrPipeReader := nil ].
	stdInWriter ifNotNil: [ stdInWriter close. stdInWriter := nil ]
]
