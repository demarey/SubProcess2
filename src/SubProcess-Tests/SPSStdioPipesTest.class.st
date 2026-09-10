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
	pipes := SPSStdioPipes withStdin: stdin stdout: stdout stderr: stderr library: library.
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
SPSStdioPipesTest >> testForSpawnUsingAsksForStdinThenStdoutThenStderr [

	| config |
	config := SPSProcessConfiguration new.
	library
		scriptPipeKind: SPSStdioPipes pipeStdinKind parent: 10 child: 11;
		scriptPipeKind: SPSStdioPipes pipeStdoutKind parent: 20 child: 21;
		scriptPipeKind: SPSStdioPipes pipeStderrKind parent: 30 child: 31.
	pipes := SPSStdioPipes forSpawnUsing: library configuration: config.
	self assert: pipes notNil.
	self assert: pipes stdin parent equals: 10.
	self assert: pipes stdout parent equals: 20.
	self assert: pipes stderr parent equals: 30.
]

{ #category : #tests }
SPSStdioPipesTest >> testForSpawnUsingClosesCreatedPipesWhenStderrFails [

	| config |
	config := SPSProcessConfiguration new.
	library
		scriptPipeKind: SPSStdioPipes pipeStdinKind parent: 10 child: 11;
		scriptPipeKind: SPSStdioPipes pipeStdoutKind parent: 20 child: 21.
	self assert: (SPSStdioPipes forSpawnUsing: library configuration: config) isNil.
	self assert: library closedFds equals: #(10 11 20 21).
]

{ #category : #tests }
SPSStdioPipesTest >> testForSpawnUsingCreatesNoPipeForSilencedStream [

	| config silencedPipes |
	config := SPSProcessConfiguration new.
	config silenceStdout.
	library
		scriptPipeKind: SPSStdioPipes pipeStdinKind parent: 10 child: 11;
		scriptPipeKind: SPSStdioPipes pipeStdoutKind parent: 20 child: 21;
		scriptPipeKind: SPSStdioPipes pipeStderrKind parent: 30 child: 31.
	silencedPipes := SPSStdioPipes forSpawnUsing: library configuration: config.
	self assert: silencedPipes stdout isNil.
	self assert: silencedPipes stdin notNil.
	self assert: silencedPipes stderr notNil.
	self assert: library createdPipes size equals: 1.
]

{ #category : #tests }
SPSStdioPipesTest >> testForSpawnUsingCreatesNoStderrPipeWhenMerged [

	| config mergedPipes |
	config := SPSProcessConfiguration new.
	config mergeStandardError.
	library
		scriptPipeKind: SPSStdioPipes pipeStdinKind parent: 10 child: 11;
		scriptPipeKind: SPSStdioPipes pipeStdoutKind parent: 20 child: 21;
		scriptPipeKind: SPSStdioPipes pipeStderrKind parent: 30 child: 31.
	mergedPipes := SPSStdioPipes forSpawnUsing: library configuration: config.
	self assert: mergedPipes stderr isNil.
	self assert: mergedPipes stdout notNil.
	self assert: library createdPipes size equals: 1.
]

{ #category : #tests }
SPSStdioPipesTest >> testStdioSpecWiresMergeIntoStdout [

	| config mergedPipes spec |
	config := SPSProcessConfiguration new.
	config mergeStandardError.
	library
		scriptPipeKind: SPSStdioPipes pipeStdinKind parent: 10 child: 11;
		scriptPipeKind: SPSStdioPipes pipeStdoutKind parent: 20 child: 21.
	mergedPipes := SPSStdioPipes forSpawnUsing: library configuration: config.
	spec := mergedPipes stdioSpec.
	self assert: spec stderrMode equals: SPSStdioSpec modeMerge.
	self assert: spec stdoutMode equals: SPSStdioSpec modePipe.
	self assert: spec stdoutFd equals: 21.
	self assert: spec stderrFd equals: 0.
]

{ #category : #tests }
SPSStdioPipesTest >> testStdioSpecWiresInheritAndSilence [

	| config silencedPipes spec |
	config := SPSProcessConfiguration new.
	config silenceStdout.
	config inheritStderr.
	config inheritStdin.
	library scriptPipeKind: SPSStdioPipes pipeStdinKind parent: 10 child: 11.
	silencedPipes := SPSStdioPipes forSpawnUsing: library configuration: config.
	spec := silencedPipes stdioSpec.
	self assert: spec stdinMode equals: SPSStdioSpec modeInherit.
	self assert: spec stdoutMode equals: SPSStdioSpec modeSilence.
	self assert: spec stderrMode equals: SPSStdioSpec modeInherit.
	self assert: spec stdoutFd equals: 0.
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

{ #category : #tests }
SPSStdioPipesTest >> testMergingStderrWhenStdoutIsNotPipedRaisesError [

	| config |
	config := SPSProcessConfiguration new.
	config inheritStdout.
	self should: [ config mergeStandardError ] raise: Error.
]
