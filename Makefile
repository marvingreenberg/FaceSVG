VERSION=3.1.0
plugin: check
	rm -f facesvg*.rbz;
	cd lib; zip -r ../facesvg-$(VERSION).rbz $$(find . -name '*rb' -o -name '*png')
	# CONVENIENCE ONLY FOR LOCAL TESTING
	rm -rf ~/'Library/Application Support/SketchUp 2024/SketchUp/Plugins/facesvg/'
	cp lib/facesvg.rb \
	   ~/'Library/Application Support/SketchUp 2024/SketchUp/Plugins'
	cp -pr lib/facesvg \
	   ~/'Library/Application Support/SketchUp 2024/SketchUp/Plugins/facesvg'

check:
	bundle exec rubocop --fail-level error lib test

test:
	ruby run_test.rb

.PHONY: test check
