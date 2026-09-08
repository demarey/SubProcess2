Class {
	#name : 'BaselineOfSubProcess',
	#superclass : 'BaselineOf',
	#category : 'BaselineOfSubProcess',
	#package : 'BaselineOfSubProcess'
}

{ #category : 'baselines' }
BaselineOfSubProcess >> baseline: spec [
	<baseline>

	spec
		for: #common
		do: [ 
			spec
				package: 'SubProcess';
				package: 'SubProcess-Tests' with: [ spec requires: #('SubProcess') ];
				group: 'default' with: #('SubProcess-Tests').
		].
]
