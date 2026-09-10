"
I mirror the native `sps_stdio_spec_t` struct passed to `sps_spawn` to describe
how each of the child's standard streams is wired: one mode (PIPE / INHERIT /
SILENCE / MERGE) and, for PIPE streams, the child-end file descriptor to
connect. For non-PIPE streams the fd is ignored by the shim (pass 0).

The layout (see native/sps_spawn.h) is:
  +0  int32    stdin_mode
  +4  int32    stdout_mode
  +8  int32    stderr_mode
  +12 int32    reserved (explicit padding so the uintptr members align on
                both 32- and 64-bit platforms)
  +16 uintptr  stdin_fd
  +24 uintptr  stdout_fd
  +32 uintptr  stderr_fd
  (40 bytes on 64-bit, 28 on 32-bit)
"
Class {
	#name : #SPSStdioSpec,
	#superclass : #FFIExternalStructure,
	#category : #SubProcess
}

{ #category : #'structure definition' }
SPSStdioSpec class >> fieldsDesc [

	"Layout must match sps_stdio_spec_t in native/sps_spawn.h."

	^ #(
		int32 stdinMode;
		int32 stdoutMode;
		int32 stderrMode;
		int32 reserved;
		size_t stdinFd;
		size_t stdoutFd;
		size_t stderrFd
	)
]

{ #category : #'class initialization' }
SPSStdioSpec class >> initialize [

	"Regenerate the field accessors from fieldsDesc when the class loads."

	self rebuildFieldAccessors
]

{ #category : #'instance creation' }
SPSStdioSpec class >> stdInMode: aStdinMode stdoutMode: aStdoutMode stderrMode: aStderrMode stdInFd: aStdinFd stdoutFd: aStdoutFd stderrFd: aStderrFd [

	^ self new
		setStdInMode: aStdinMode
		stdoutMode: aStdoutMode
		stderrMode: aStderrMode
		stdInFd: aStdinFd
		stdoutFd: aStdoutFd
		stderrFd: aStderrFd
]

{ #category : #constants }
SPSStdioSpec class >> modeForStrategy: aStrategySymbol [

	"Map a configuration strategy (#pipe, #inherit, #silence, #merge) to the
	 native sps_stdio_mode_t value. #pipe is the default."

	^ aStrategySymbol caseOf: {
		[ #inherit ] -> [ self modeInherit ].
		[ #silence ] -> [ self modeSilence ].
		[ #merge ] -> [ self modeMerge ] }
		otherwise: [ self modePipe ]
]

{ #category : #constants }
SPSStdioSpec class >> modeInherit [

	"Child keeps the caller's descriptor for this stream."

	^ 1
]

{ #category : #constants }
SPSStdioSpec class >> modeMerge [

	"stderr is wired onto the resolved stdout. Valid only for stderr."

	^ 3
]

{ #category : #constants }
SPSStdioSpec class >> modePipe [

	"Connect an sps_pipe child end to this stream."

	^ 0
]

{ #category : #constants }
SPSStdioSpec class >> modeSilence [

	"Redirect this stream to /dev/null (or NUL)."

	^ 2
]

{ #category : #'instance creation' }
SPSStdioSpec >> setStdInMode: aStdinMode stdoutMode: aStdoutMode stderrMode: aStderrMode stdInFd: aStdinFd stdoutFd: aStdoutFd stderrFd: aStderrFd [

	self stdinMode: aStdinMode.
	self stdoutMode: aStdoutMode.
	self stderrMode: aStderrMode.
	self stdinFd: aStdinFd.
	self stdoutFd: aStdoutFd.
	self stderrFd: aStderrFd.
	^ self
]
