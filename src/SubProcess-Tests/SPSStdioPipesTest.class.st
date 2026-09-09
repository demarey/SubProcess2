"
I unit test the descriptor closing policy of SPSStdioPipes: closing all ends
on failure, and closing only the child ends plus both stdin ends on success.
"
Class {
	#name : #SPSStdioPipesTest,
	#superclass : #TestCase,
	#instVars : [
		'library',
		'stdin',
		'stdout',
		'stderr',
		'pipes'
	],
	#category : #'SubProcess-Tests'
}

{ #category : #running }
SPSStdioPipesTest >> setUp [

	super setUp.
	library := SPSMockSpawnLibrary new.
	stdin := SPSPipeEnds parent: 10 child: 11.
	stdout := SPSPipeEnds parent: 20 child: 21.
	stderr := SPSPipeEnds parent: 30 child: 31.
	pipes := SPSStdioPipes stdin: stdin stdout: stdout stderr: stderr library: library.
]

{ #category : #tests }
SPSStdioPipesTest >> testCloseAfterSuccessfulSpawnClosesChildEndsAndStdin [

	pipes closeAfterSuccessfulSpawn.
	self assert: library closedFds equals: #(10 11 21 31).
]

{ #category : #tests }
SPSStdioPipesTest >> testCloseAfterSuccessfulSpawnKeepsParentStdoutStderrOpen [

	pipes closeAfterSuccessfulSpawn.
	self assert: (library closedFds includes: 20) not.
	self assert: (library closedFds includes: 30) not.
]

{ #category : #tests }
SPSStdioPipesTest >> testCloseAllClosesEveryDescriptor [

	pipes closeAll.
	self assert: library closedFds equals: #(10 11 20 21 30 31).
]

{ #category : #tests }
SPSStdioPipesTest >> testCloseFdIgnoresNil [

	| aNilPipe |
	aNilPipe := SPSPipeEnds parent: nil child: nil.
	pipes closeFd: aNilPipe parent.
	pipes closeFd: aNilPipe child.
	self assert: library closedFds isEmpty.
]

{ #category : #tests }
SPSStdioPipesTest >> testAccessors [

	self assert: pipes stdin identicalTo: stdin.
	self assert: pipes stdout identicalTo: stdout.
	self assert: pipes stderr identicalTo: stderr.
]
