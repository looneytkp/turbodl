#!/bin/env bash
set -ex
count=1
count1=0
while [ $count -le 63 ]; do
	curl -s -X GET "https://turbodl.xyz/wp-json/wp/v2/posts?page=$count&per_page=12" > 'file.x'
	while [ $count1 -lt 11 ]; do
		title=$(cat file | jq -r ".[$count1].title.rendered" | sed -e 's/&#8211;/-/' -e "s/&#8217;/'/" -e "s/&#038;/\&/" -e "s/&#8216;/'/" -e 's/&#8220;/"/' -e 's/&#8221;/"/')
		if [ "$title" == null ]; then break; fi
		echo "$title" >> titles.txt
		count1=$((count1+1))
	done
	count1=0
	count=$((count+1))
done
rm file.x
