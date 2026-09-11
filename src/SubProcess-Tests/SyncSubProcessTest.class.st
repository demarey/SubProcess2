Class {
	#name : #SyncSubProcessTest,
	#superclass : #SPSProcessTestCase,
	#category : #'SubProcess-Tests'
}

{ #category : #tests }
SyncSubProcessTest >> testRunningANonExistingCommand [
	
	process := self newProcessConfigurationForNonExistingCommand sync.
	
	self
		should: [ process run ]
		raise: SPSError
		withExceptionDo: [ :error |
			self 
				assert: (error messageText includesSubstring: 'No such file or directory')
				description: 'Expecting "No Such file ..." but got ', error messageText.
		].
	
	self assert: process isComplete.
	self deny: process isSpawnSuccess.
	self assert: process stdErr isEmpty.
	self assert: process stdOut isEmpty.
	self assert: process exitCode isNil
]

{ #category : #tests }
SyncSubProcessTest >> testRunningBasicCommand [
	
	self skipIfRunningOnWindows.
	process := SPSProcessConfiguration new
		command: '/bin/ls';
		sync.
	
	process run.
	
	self assert: process isComplete.
	self assert: process isSpawnSuccess.
	self assert: process isExitSuccess.
	self assert: process stdErr isEmpty.
	self deny: process stdOut isEmpty.

]

{ #category : #tests }
SyncSubProcessTest >> testRunningCommandWithNonAsciiOutputRoundTrips [

	"Child echoes a non-ASCII string; it must come back present in the decoded
	 output. Uses a platform-appropriate echo command."

	| output expected |
	expected := 'café wörld'.
	process := self isRunningOnWindows
		ifTrue: [
			SPSProcessConfiguration new
				command: 'C:\Windows\System32\cmd.exe';
				arguments: { '/C'. 'echo '. expected };
				encoding: 'utf8';
				sync ]
		ifFalse: [
			SPSProcessConfiguration new
				command: '/bin/echo';
				arguments: { expected };
				encoding: 'utf8';
				sync ].

	process run.

	self assert: process isComplete.
	self assert: process isSpawnSuccess.
	self assert: process isExitSuccess.
	self assert: (process stdOut includesSubstring: expected).
]

{ #category : #tests }
SyncSubProcessTest >> testRunningCommandWithNonZeroExitCode [

	self skipIfRunningOnWindows.
	process := SPSProcessConfiguration new
		command: '/bin/sh';
		arguments: { '-c'. ('exit {1}' format: { self class nonZeroExitCode }) };
		sync.
	
	process run.
	
	self assert: process isComplete.
	self assert: process isSpawnSuccess.
	self assert: process exitCode equals: self class nonZeroExitCode.
	self deny: process isExitSuccess.
]

{ #category : #tests }
SyncSubProcessTest >> testRunningCommandWithNonZeroExitCodeOnWindows [

	self isRunningOnWindows ifFalse: [ self skip: 'skipping windows test'].
	process := SPSProcessConfiguration new
		windowsShellCommand;
		addArgument: ('exit {1}' format: { self class nonZeroExitCode });
		sync.
	
	process run.
	
	self assert: process isComplete.
	self assert: process isSpawnSuccess.
	self assert: process exitCode equals: self class nonZeroExitCode.
	self deny: process isExitSuccess.
]

{ #category : #tests }
SyncSubProcessTest >> testRunningBasicCommandOnWindows [
	
	| output |
	
	self isRunningOnWindows ifFalse: [ self skip: 'skipping windows test'].
	process := SPSProcessConfiguration new
		command: 'C:\Windows\System32\systeminfo.exe';
		sync.
	
	process run.
	
	self assert: process isComplete.
	self assert: process isSpawnSuccess.
	self assert: process isExitSuccess.
	self assert: process stdErr isEmpty.
	self deny: process stdOut isEmpty.
	output := process stdOut.
	self assert: (output includesSubstring: 'Microsoft Windows').
]

{ #category : #tests }
SyncSubProcessTest >> testRunningSilencedCommandProducesNoOutput [

	self skipIfRunningOnWindows.
	process := SPSProcessConfiguration new
		command: '/bin/echo';
		arguments: { 'hello' };
		silenceStdout;
		sync.

	process run.

	self assert: process isComplete.
	self assert: process isSpawnSuccess.
	self assert: process isExitSuccess.
	self assert: process stdOut isEmpty.
	self assert: process stdErr isEmpty.
]

{ #category : #tests }
SyncSubProcessTest >> testRunningCommandWithMergedStderrCapturesBothOnStdout [

	| output |
	self skipIfRunningOnWindows.
	process := SPSProcessConfiguration new
		collectsOutput;
		mergeStandardError;
		command: '/bin/sh';
		arguments: { '-c'. 'echo to-stdout; echo to-stderr 1>&2' };
		sync.

	process run.

	self assert: process isComplete.
	self assert: process isSpawnSuccess.
	self assert: process isExitSuccess.
	self assert: process stdErr isEmpty.
	output := process stdOut.
	self assert: (output includesSubstring: 'to-stdout').
	self assert: (output includesSubstring: 'to-stderr').
]

{ #category : #tests }
SyncSubProcessTest >> testRunningCommandWithInheritedStdout [

	"Verify #inheritStdout: the child writes its standard output directly onto
	 the caller's file descriptor 1. We temporarily redirect fd 1 to a scratch
	 file, run the child, restore fd 1, then read the marker back from the file."

	| contents tempFile |
	self skipIfRunningOnWindows.
	tempFile := Smalltalk imagePath asFileReference parent / 'inherit-scratch.txt'.
	contents := self
		redirectingStandardOutputInto: tempFile
		during: [
			process := SPSProcessConfiguration new
				command: '/bin/sh';
				arguments: { '-c'. 'echo inherited-marker' };
				inheritStdout;
				sync.

			process run ].

	self assert: process isComplete.
	self assert: process isSpawnSuccess.
	self assert: process isExitSuccess.
	self deny: contents isEmpty.
	self assert: (contents includesSubstring: 'inherited-marker').
]

{ #category : #tests }
SyncSubProcessTest >> testRunningCommandInGivenWorkingDirectory [	
	| dir config |
	dir := Smalltalk imagePath asFileReference parent / 'pharo-local'.
	config := SPSProcessConfiguration new
		workingDirectory: dir;
		command: '/bin/ls';
		yourself.
	OSPlatform current isWindows 
		ifTrue: [ config
						windowsShellCommand;
						addArgument: 'dir' ]	.
	process := config sync.
	
	process run.
	
	self assert: process isComplete.
	self assert: process isSpawnSuccess.
	self assert: process isExitSuccess.
	self assert: process exitCode equals: self class successExitCode.
	self assert: process stdErr isEmpty.
	self assert: (process stdOut includesSubstring: 'ombu-sessions').

]
