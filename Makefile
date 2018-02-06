plugin: check
	rm facesvg.rbz; zip -r facesvg.rbz facesvg.rb facesvg/*rb
	# CONVENIENCE ONLY
	cp -f facesvg/*rb \
	   ~/'Library/Application Support/SketchUp 2017/SketchUp/Plugins/facesvg/'

check:
	PATH=$$PATH:/usr/local/bin rubocop --auto-correct facesvg.rb facesvg
