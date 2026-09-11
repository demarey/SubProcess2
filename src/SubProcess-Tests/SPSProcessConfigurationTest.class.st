"
I unit test the platform-specific default encoding chosen by
SPSProcessConfiguration.
"
Class {
	#name : #SPSProcessConfigurationTest,
	#superclass : #TestCase,
	#category : #'SubProcess-Tests'
}

{ #category : #tests }
SPSProcessConfigurationTest >> testDefaultEncodingIsPerPlatform [

	| default |
	default := SPSProcessConfiguration new encoding.
	self assert: default isString.
	self assert: (OSPlatform current isWindows
		ifTrue: [ default = 'cp-1252' ]
		ifFalse: [ default = 'utf8' ]).
]
