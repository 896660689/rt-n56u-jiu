#!/bin/sh
TRIGS="7621"
CKE="a4179586"

git config --global user.name "896660689@qq.com"
git config --global user.email "896660689@qq.com@github.com"

gitver="$(git rev-parse --short=7 HEAD 2>/dev/null)"
msg="build trigger: $gitver"

for repo in $TRIGS ; do
	cd /opt
	if [ -f /opt/${repo}.yml ]; then
		git clone --depth=1 https://896660689:$CKE@github.com/896660689/$repo.git && cd $repo
		echo "$(LANG=C date) $gitver" >> Build.log
		cp -f /opt/${repo}.yml .travis.yml
		git add .
		git commit -m "$msg"
		git remote set-url origin https://896660689:$CKE@github.com/896660689/$repo.git
		git push
	fi
done
