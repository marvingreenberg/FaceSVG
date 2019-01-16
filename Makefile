VERSION=2.3.0

SK2017 := /Users/mgreenberg/Library/Application Support/SketchUp 2017/SketchUp/Plugins

plugin: check
	rm facesvg*.rbz; zip -r facesvg-$(VERSION).rbz facesvg.rb facesvg/*rb
	# CONVENIENCE FOR TESTING ONLY
	unzip -oq facesvg-$(VERSION).rbz -d '$(SK2017)'


check:
	PATH=$$PATH:/usr/local/bin rubocop facesvg.rb facesvg

