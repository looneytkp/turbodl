#!/bin/env bash

if [ ! -e /usr/bin/jq ]; then echo "install jq"; exit; fi
if [ -d ~/.tmp ]; then
	cd ~/.tmp; rm movies/* errors/* today.txt output* 'info' file.x data titles.txt 2> /dev/null
else
	mkdir -p ~/.tmp/movies ~/.tmp/errors; cd ~/.tmp
fi

DL_MOVIEDATA(){
	#function to use when both OMDB and tracktv API fail to get movie details
	unset IMG2 CAST2 GENRE2 LINKS2
	if [ ! -e moviedata ]; then
		wget -q -O moviedata $(grep "$OUTPUT" output2 | grep -o http.*html)		#grab movie page from lightdl
	fi
	IMG2=$(grep -o ^"<a href.*media-amazon.*jpg" moviedata | sed 's/jpg".*/jpg"/')		#get image URL
	CAST2=$(grep -o ^"Stars.*<" moviedata | sed -e "s/Stars/Cast/" -e "s/<//")		#get cast details
	GENRE2=$(grep ^Genre moviedata | sed -e 's/Genre: //' -e "s/<br.*//")		#get genre details
	if grep -qi 'documentary' <<< "$GENRE"; then continue; fi	#skip documentaries
	LINKS2=$(grep ^"<span style=\"font-family.*http.*a>" moviedata | sed -e "s/.*<a/<a/" -e "s/a>.*/a>/")	#get download links
	export IMG2 CAST2 GENRE2 LINKS2		#export variables to use outside the function
}

#curl -s -X POST https://content.dropboxapi.com/2/files/download --header "Authorization: Bearer DlS2vDBOAr4AAAAAAAABck-oi1CylO-l-Dg6lddfRy4vcq5iH8WJxU6jNkK__uGY" --header "Dropbox-API-Arg: {\"path\": \"/dev/movie list.txt\"}" > 'movie list.txt'		#download list of movies from dropbox
#get movies posted to website

COUNT=1; COUNT1=0
echo '---script starts above this---' > 'movie list.txt'
while true; do
	curl -s -X GET "https://turbodl.xyz/wp-json/wp/v2/posts?page=$COUNT&per_page=100" > file.x
	if grep -q 'rest_post_invalid_page_number' file.x; then break; fi
	while [ $COUNT1 -lt 100 ]; do
		title=$(cat file.x | jq -r ".[$COUNT1].title.rendered" | sed -e 's/&#8211;/-/g' -e "s/&#8217;/'/g" -e "s/&#038;/\&/g" -e "s/&#8216;/'/g" -e 's/&#822[0-1];/"/g' -e 's/&amp;/\&/g')
		if [ "$title" == null ]; then break; fi
		grep "$title" 'movie list.txt' || echo "$title" >> 'movie list.txt'
		COUNT1=$((COUNT1+1))
	done
	break #COUNT1=0; COUNT=$((COUNT+1))
done

wget -q -O data "https://lightdlmovies.blogspot.com/search/label/MOVIES"		#download lightdl movies page
grep ^'<a href=.*html.*title=.*</a>' data | sed -e "s/'>.*//" -e "s/.*title='//" -e "s/<\/a>//" > output	#direct titles of movies into output file
grep ^'<a href=.*html.*title=.*</a>' data | sed "s/'>.*//" > output2	#direct urls of movies into output2 file
echo -e ""$(date)"\\n--------------------------------" > 'today.txt'

if [ "$USER" == root ]; then
	exec 3>&1 4>&2
	trap 'exec 2>&4 1>&3' 0 1 2 3
	exec 1>logs.txt 2>&1
fi
set -ex

while IFS= read -r OUTPUT; do	#loop through movie titles in output file
	echo -e "\\n$OUTPUT\\n------------------------------"
	if [ -e moviedata ]; then rm moviedata; fi
	OUTPUT=$(grep "$OUTPUT" output | sed -e 's/[ ]$//')		#removes spaces if any at the end of titles
	YEAR=$(grep -oE '[0-9][0-9][0-9][0-9]$' <<< "$OUTPUT" || echo 'null')
	if grep -q 'null' <<< "$YEAR"; then sed -i "1s/^/$OUTPUT\\n/" 'movie list.txt'; echo "$OUTPUT   --> year not found" >> 'today.txt'; continue; fi
	OUTPUT2=$(sed 's/[ -.][0-9][0-9][0-9][0-9]$//' <<< "$OUTPUT")
	if grep -q "$OUTPUT2.*$YEAR" 'movie list.txt'; then echo "$OUTPUT   --> already posted" >> 'today.txt'; continue; fi #func		#skip movies that are already posted
	if grep -q '&' <<< "$OUTPUT2"; then
		OUTPUT3=$(sed 's/\&/and/' <<< "$OUTPUT2")
		if grep -q "$OUTPUT3.*$YEAR" 'movie list.txt'; then echo "$OUTPUT   --> already posted" >> 'today.txt'; continue; fi	#func
	fi
	OMDB_NAME=$(sed "s/ /%20/g" <<< "$OUTPUT2") #|grep -ioE ^'([a-z].*[a-z]|[0-9].*[a-z]|[a-z].*[0-9]')#format current title by replacing spaces with %20 to work with API's
#	PATTERN=$(sed -e 's/%20//g' -e "s/[ -.]//g" -e 's/\(.\)/\1.*/g' -e 's/..$//' <<< "$OMDB_NAME")		#format title into pattern used in finding download links

	if grep -qo '[0-9][0-9][0-9][0-9]' <<< $YEAR; then
		curl -s -H "Accept: application/json" -H "Content-Type: application/json" "http://www.omdbapi.com/?t=$OMDB_NAME&y=$YEAR&type=movie&plot=short&apikey=7759dbc7" | jq "." > "info" 2> /dev/null	#OMDB API to get details of movie
	else
		curl -s -H "Accept: application/json" -H "Content-Type: application/json" "http://www.omdbapi.com/?t=$OMDB_NAME&type=movie&plot=short&apikey=7759dbc7" | jq "." > "info" 2> /dev/null
	fi
	if grep -qE '("Response": "False"|"Error": "Movie not found!")' info; then
		curl -s --header "Content-Type: application/json" --header "trakt-api-version: 2" --header "trakt-api-key: 64ba02e985f18ec3a00186209b3605cfbbeedf9890898e3a06b8e020111e8194" "https://api.trakt.tv/search/movie?query=$OMDB_NAME" | jq "." > 'info'  2> /dev/null		#trakttv API, runs when OMDB API fails to get details because of improper title format
		C=0
		while true; do
			T=$(cat 'info' | jq -r ".[$C].movie.title")
			if [ "$T" == null ]; then break; fi
			Y=$(cat 'info' | jq -r ".[$C].movie.year")
			if [ "$Y" == $YEAR ]; then
				IMDB_ID=$(cat 'info' | jq -r ".[$C].movie.ids.imdb")
				curl -s -H "Accept: application/json" -H "Content-Type: application/json" "http://www.omdbapi.com/?i=$IMDB_ID&plot=short&apikey=7759dbc7" | jq "." > "info" 2> /dev/null	#OMDB API to get movie details with imdb ID when finding with name fails
				break
			else
				C=$((C+1))
			fi
		done
		if [ "$T" == null ]; then
			DL_MOVIEDATA	#function
			echo -e "<div style=\"text-align: center;\">\\n[ NO DESCRIPTION ]\\n\\nIMDB Rating: [ NULL ]\\nCast: $CAST2\\nGenre: [ $GENRE2 ]\\n\\n$LINKS2\\n</div>\\n\\nTags: [ $GENRE2, $YEAR ]" > errors/"$OUTPUT"	#place everything in errors directory because it's incomplete
			sed -i "1s/^/$OUTPUT\\n/" 'movie list.txt'
			echo "$OUTPUT   --> incomplete" >> 'today.txt'		#place title in file to upload to dropbox & mail
			rm moviedata
			continue
		fi

#		if grep -q 'imdb' info; then
#			RESULT=$(grep 'imdb":' 'info')
#			while IFS= read -r IMDB_ID; do		#loop through traktv results for imdb ID
#				if grep null <<< "$IMDB_ID"; then
#					continue	#skip current result if imdb ID is null
#				else
#					IMDB_ID=$(sed -e 's/.*: "//' -e 's/",//' <<< "$IMDB_ID")	#get imdb ID if result is not null
#					curl -s -H "Accept: application/json" -H "Content-Type: application/json" "http://www.omdbapi.com/?i=$IMDB_ID&plot=short&apikey=7759dbc7" | jq "." > "info" 2> /dev/null	#OMDB API to get movie details with imdb ID when finding with name fails
#					break
#				fi
#			done <<< "$RESULT"
#		else
#			DL_MOVIEDATA	#function
#			{
#				echo -e "<div style=\"text-align: center;\">\\n[ NO DESCRIPTION ]\\n\\nIMDB Rating: [ NULL ]\\nCast: $CAST2\\nGenre: [ $GENRE2 ]\\n\\n$LINKS2\\n</div>"
#			} > errors/"$OUTPUT"	#place everything in errors directory because it's incomplete
#			echo "$OUTPUT" >> 'movie list.txt'
#			echo "$OUTPUT   --> error" >> 'today.txt'		#place title in file to upload to dropbox & mail
#			rm moviedata
#			continue
#		fi
	fi

	#execute if OMDB API is successful
	RATING=$(grep "imdbRating" 'info' | sed -e 's/.*: "//' -e 's/",//')		#get movie rating
	if [ "$RATING" != 'N/A' ]; then
		RATE=$(sed 's/\.//' <<< "$RATING")
		if [ $RATE -lt 55 ]; then echo "$OUTPUT   --> rating: $RATING" >> 'today.txt'; continue; fi	#skip movie if rating is below 5.5
	else
		echo "$OUTPUT   --> rating: $RATING" >> 'today.txt'		#place title in file to upload to dropbox & mail
	fi
	GENRE=$(grep "Genre" 'info' | sed -e 's/.*: "//' -e 's/",//')	#get genre
	if grep -q 'N/A' <<< "$GENRE"; then DL_MOVIEDATA && GENRE="$GENRE2"; fi		#try to get genre from DL_MOVIEDATA function if genre is N/A
	if grep -qi 'documentary' <<< "$GENRE"; then echo "$OUTPUT   --> documentary" >> 'today.txt'; continue; fi	#skip documentaries
	A=$(grep "Title" 'info' | sed -e 's/.*: "//' -e 's/",//')	#get title
	B=$(grep "Year.*:" 'info' | sed -e 's/.*: "//' -e 's/",//')		#get year
	TITLE="$A ($B)"		#format title and year
	PLOT=$(grep "Plot" 'info' | sed -e 's/.*: "//' -e 's/",//')		#get movie plot
	CAST=$(grep "Actors" 'info' | sed -e 's/.*: "//' -e 's/",//')		#get cast
	if grep -q 'N/A' <<< "$CAST"; then DL_MOVIEDATA && CAST=$(sed 's/Cast: //' <<< "$CAST2"); fi	#try to get cast from DL_MOVIEDATA function if cast is N/A
	#LINKS=$(grep -iE ^"<span style=\"font-family.*<a href=.*>$PATTERN.*a>" data | sed -e "s/.*<a/<a/" -e "s/a>.*/a>/")		#get download links
	LINKS=$(wget -q -O - $(grep "$OUTPUT" output2 | grep -o http.*html) | grep ^"<span style=\"font-family.*http.*a>" | sed -e "s/.*<a/<a/" -e "s/a>.*/a>/" -e 's/CLICK HERE FOR SUBTITLES /Subtitles/')	#grab movie page from lightdl & grep links
	md5=$(md5sum <<< $LINKS)
	#if grep -qiE "(camrip|hdts|hdtc)"
	CHECK=$(echo -e "$A\\n$B\\n$RATING\\n$GENRE" | grep -o 'N/A' || echo 'A/N')
	if grep -q 'N/A' <<< "$CHECK"; then
		sed -i "1s/^/$OUTPUT\\n/" 'movie list.txt'
		echo -e "<div style=\"text-align: center;\">\\n$PLOT\\n\\nIMDB Rating: $RATING\\nCast: $CAST\\nGenre: $GENRE\\n\\n$LINKS\\n</div>\\n\\nTags: $GENRE, $B" > errors/"$OUTPUT"
		continue
	else
		if grep -qE "($A|$OUTPUT2|$TITLE)" 'movie list.txt'; then echo "$OUTPUT   --> already posted" >> 'today.txt'; continue; fi	#func	#skip movies that are already posted
		IMG=$(grep "Poster" 'info' | sed -e 's/.*: "//' -e 's/",//')	#get image URL
		if grep -q 'N/A' <<< "$IMG"; then DL_MOVIEDATA && IMG="$IMG2"; fi	#try to get image URL from DL_MOVIEDATA function if image URL is N/A
		curl -s "$IMG" -o movies/"$OUTPUT".jpg		#download img
		#check img dimension
		W=$(identify -format "%w" movies/"$OUTPUT".jpg)> /dev/null
		H=$(identify -format "%h" movies/"$OUTPUT".jpg)> /dev/null
		if [ $W -gt 330 ] || [ $W -lt 270 ]; then
			mv movies/"$OUTPUT".jpg errors/"$OUTPUT".jpg
			echo "$OUTPUT   --> img width problem" >> 'today.txt'
			sed -i "1s/^/$TITLE\\n/" 'movie list.txt'
			echo -e "<div style=\"text-align: center;\">\\n$PLOT\\n\\nIMDB Rating: $RATING\\nCast: $CAST\\nGenre: $GENRE\\n\\n$LINKS\\n</div>\\n\\nTags: $GENRE, $B" > errors/"$OUTPUT"
			continue
		elif [ $H -gt 480 ] || [ $H -lt 400 ]; then
			mv movies/"$OUTPUT".jpg errors/"$OUTPUT".jpg
			echo "$OUTPUT   --> img height problem" >> 'today.txt'
			sed -i "1s/^/$TITLE\\n/" 'movie list.txt'
			echo -e "<div style=\"text-align: center;\">\\n$PLOT\\n\\nIMDB Rating: $RATING\\nCast: $CAST\\nGenre: $GENRE\\n\\n$LINKS\\n</div>\\n\\nTags: $GENRE, $B" > errors/"$OUTPUT"
			continue
		else
			sed -i "1s/^/$TITLE\\n/" 'movie list.txt'
			echo "$TITLE" >> 'today.txt'		#place title in file to upload to dropbox & mail
			echo -e "<div style=\"text-align: center;\">\\n$PLOT\\n\\nIMDB Rating: $RATING\\nCast: $CAST\\nGenre: $GENRE\\n\\n$LINKS\\n</div>\\n\\nTags: $GENRE, $B" > movies/"$OUTPUT"
			echo "$TITLE #$OUTPUT" >> titles.txt
		fi
	fi
#	if [ "$USER" == root ]; then
#	echo | mutt -s "$TITLE" -i movies/"$OUTPUT" -a movies/"$OUTPUT".jpg -- Ud37asAUd8a7@turbodl.xyz
#	fi
done < output	#end of loop

#curl -s -X POST https://content.dropboxapi.com/2/files/upload --header "Authorization: Bearer DlS2vDBOAr4AAAAAAAABck-oi1CylO-l-Dg6lddfRy4vcq5iH8WJxU6jNkK__uGY" --header "Dropbox-API-Arg: {\"path\": \"/dev/movie list.txt\",\"mode\": \"overwrite\",\"autorename\": false,\"mute\": false,\"strict_conflict\": false}" --header "Content-Type: application/octet-stream" --data-binary @'movie list.txt' > /dev/null		#upload titles file to dropbox
if [ "$USER" == root ]; then
	echo -e "\\n---sorting randomly---"
	SORTED_POSTS=$(cat titles.txt | sort -Rr)
	while IFS= read -r SORTED; do
		E=$(grep -o '#.*' <<< "$SORTED" | sed 's/#//')
		F=$(sed 's/ #.*//' <<< "$SORTED")
		echo | mutt -s "$F" -i movies/"$E" -a movies/"$E".jpg -- Ud37asAUd8a7@turbodl.xyz
	done <<< "$SORTED_POSTS"

	if [ -z "$(ls -A errors)" ]; then
		echo | mutt -s 'turbodlbot' -i 'today.txt' -- persie@turbodl.xyz 'info@turbodl.xyz'
	else
		echo | mutt -s 'turbodlbot' -i 'today.txt' -a errors/* -- persie@turbodl.xyz 'info@turbodl.xyz'
	fi
	echo | mutt -s 'turbodlbot log' -i titles.txt -a logs.txt 'movie list.txt' -- persie@turbodl.xyz
fi
