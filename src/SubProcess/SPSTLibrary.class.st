"
I provide access to the native spawn shim (`SPSSpawnLibrary uniqueInstance`) for
classes that perform FFI calls on child-process file descriptors or handles.
"
Trait {
	#name : #SPSTLibrary,
	#category : #SubProcess
}

{ #category : #'ffi - library' }
SPSTLibrary >> ffiLibrary [

	^ SPSSpawnLibrary uniqueInstance
]
