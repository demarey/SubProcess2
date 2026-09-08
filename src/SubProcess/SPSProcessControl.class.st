"
I terminate a spawned child OS process in a platform-appropriate way. I
delegate to the native spawn shim, which uses SIGKILL on Unix and
TerminateProcess on Windows, so this class stays fully platform-agnostic.

Used by SPSAsyncProcess >> terminate and SPSProcess >> terminate.
"
Class {
	#name : #SPSProcessControl,
	#superclass : #Object,
	#category : #SubProcess
}

{ #category : #terminating }
SPSProcessControl class >> terminateProcess: aToken [

	SPSSpawnLibrary uniqueInstance killPid: aToken
]
