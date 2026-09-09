Class {
	#name : #SyncSubProcessTest,
	#superclass : #TestCase,
	#instVars : [
		'process'
	],
	#category : #'SubProcess-Tests'
}

{ #category : #constants }
SyncSubProcessTest class >> nonZeroExitCode [

	"Exit code used to assert a non-successful process completion."

	^ 42
]

{ #category : #constants }
SyncSubProcessTest class >> successExitCode [

	"Exit code asserted on successful process completion."

	^ 0
]

{ #category : #configuring }
SyncSubProcessTest >> skipIfRunningOnWindows [

	self isRunningOnWindows ifTrue: [ self skip: 'skipping unix test']
]

{ #category : #configuring }
SyncSubProcessTest >> isRunningOnWindows [

	^ OSPlatform current isWindows
]

{ #category : #running }
SyncSubProcessTest >> tearDown [

	process ifNotNil: [ process terminate ].
	super tearDown.
]

{ #category : #tests }
SyncSubProcessTest >> testRunningANonExistingCommand [
	
	process := SPSProcessConfiguration new
		command: 'non_exisiting_command';
		arguments: #('foo' 'bar');
		sync.
	
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
