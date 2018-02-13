plugin:
	rm facesvg.rbz; zip -r facesvg.rbz facesvg.rb facesvg/*rb

check:
	PATH=$$PATH:/usr/local/bin rubocop --auto-correct facesvg.rb facesvg

chkgit:
	# Error indicate uncommited changes
	git diff-index --quiet  HEAD --

release: chkgit plugin
	  git ci -m 'Update rbz release' facesvg.rbz
