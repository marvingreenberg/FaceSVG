VERSION=2.3.0
plugin: check
	rm -f facesvg*.rbz; cd lib; zip -r ../facesvg-$(VERSION).rbz facesvg.rb facesvg/*rb
	# CONVENIENCE ONLY
	-mkdir \
	   ~/'Library/Application Support/SketchUp 2022/SketchUp/Plugins/facesvg/'
	cp lib/facesvg.rb \
	   ~/'Library/Application Support/SketchUp 2022/SketchUp/Plugins'
	cp -f lib/facesvg/*rb \
	   ~/'Library/Application Support/SketchUp 2022/SketchUp/Plugins/facesvg/'

check:
	rubocop lib
