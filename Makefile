VERSION=2.2.0

plugin: check
	rm facesvg*.rbz; zip -r facesvg-$(VERSION).rbz facesvg.rb facesvg/*rb
	# CONVENIENCE ONLY
	cp facesvg.rb \
	   ~/'Library/Application Support/SketchUp 2016/SketchUp/Plugins'
	-mkdir \
	   ~/'Library/Application Support/SketchUp 2016/SketchUp/Plugins/facesvg/'
	cp -f facesvg/*rb \
	   ~/'Library/Application Support/SketchUp 2016/SketchUp/Plugins/facesvg/'
	-mkdir \
	   ~/'Library/Application Support/SketchUp 2017/SketchUp/Plugins/facesvg/'
	cp facesvg.rb \
	   ~/'Library/Application Support/SketchUp 2017/SketchUp/Plugins'
	cp -f facesvg/*rb \
	   ~/'Library/Application Support/SketchUp 2017/SketchUp/Plugins/facesvg/'

check:
	PATH=$$PATH:/usr/local/bin rubocop facesvg.rb facesvg
