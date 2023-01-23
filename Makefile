VERSION=2.3.0
plugin: check
	rm -f facesvg*.rbz; zip -r facesvg-$(VERSION).rbz facesvg.rb facesvg/*rb
	# CONVENIENCE ONLY
	-mkdir \
	   ~/'Library/Application Support/SketchUp 2022/SketchUp/Plugins/facesvg/'
	cp facesvg.rb \
	   ~/'Library/Application Support/SketchUp 2022/SketchUp/Plugins'
	cp -f facesvg/*rb \
	   ~/'Library/Application Support/SketchUp 2022/SketchUp/Plugins/facesvg/'

check:
	PATH=$$PATH:/usr/local/bin rubocop facesvg.rb facesvg
