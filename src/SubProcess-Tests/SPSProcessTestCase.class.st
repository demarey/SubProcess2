Class {
	#name : #SPSProcessTestCase,
	#superclass : #TestCase,
	#instVars : [
		'process'
	],
	#category : #'SubProcess-Tests'
}

{ #category : #constants }
SPSProcessTestCase class >> nonZeroExitCode [

	"Exit code used to assert a non-successful process completion."

	^ 42
]

{ #category : #constants }
SPSProcessTestCase class >> successExitCode [

	"Exit code asserted on successful process completion."

	^ 0
]

{ #category : #'helpers - building' }
SPSProcessTestCase >> newProcessConfigurationForNonExistingCommand [

	^ SPSProcessConfiguration new
		command: 'non_exisiting_command';
		arguments: #('foo' 'bar');
		yourself
]

{ #category : #'helpers - building' }
SPSProcessTestCase >> newProcessConfigurationWithShellCommand: anExpression [

	"Answer a configuration running anExpression through the platform's shell."

	| config |
	config := SPSProcessConfiguration new.
	self isRunningOnWindows
		ifTrue: [ config command: 'C:\Windows\System32\cmd.exe'; addArgument: '/C'; addArgument: anExpression ]
		ifFalse: [ config command: '/bin/sh'; arguments: { '-c'. anExpression } ].
	^ config
]

{ #category : #configuring }
SPSProcessTestCase >> isRunningOnWindows [

	^ OSPlatform current isWindows
]

{ #category : #configuring }
SPSProcessTestCase >> skipIfRunningOnWindows [

	self isRunningOnWindows ifTrue: [ self skip: 'skipping unix test']
]

{ #category : #running }
SPSProcessTestCase >> tearDown [

	process ifNotNil: [ process terminate ].
	super tearDown.
]

{ #category : #'helpers - waiting' }
SPSProcessTestCase >> waitFor: aBlock within: aDuration [

	"Poll every 20ms until aBlock answers true or aDuration elapses.
	 Answer whether aBlock answered true before the deadline."

	| deadline |
	deadline := DateAndTime now + aDuration.
	[ aBlock value or: [ DateAndTime now > deadline ] ]
		whileFalse: [ (self class waitForPollDelay) asDelay wait ].
	^ aBlock value
]

{ #category : #constants }
SPSProcessTestCase class >> waitForPollDelay [

	"Delay between polls while #waitFor: polls its predicate."

	^ 20 milliSeconds
]
