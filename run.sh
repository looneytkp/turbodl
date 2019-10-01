#!/bin/env bash

if [ ! -e /usr/bin/jq ]; then echo "install jq"; exit; fi
if [ -d ~/.tmp ]; then
    cd ~/.tmp; rm movies/* errors/* today.txt output* 'info' file.x data titles.txt 2> /dev/null
else
    mkdir -p ~/.tmp/movies ~/.tmp/errors; cd ~/.tmp
fi

DL_MOVIEDATA(){
    #function for when both OMDB and tracktv API fail to get movie data
    unset IMG2 CAST2 GENRE2 LINKS2
    if [ ! -e moviedata ]; then
        curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s -o moviedata $(grep "$OUTPUT" output2 | grep -o http.*html)		#grab movie page from lightdl
    fi
    IMG2=$(grep -o ^"<a href.*media-amazon.*jpg" moviedata | sed 's/jpg".*/jpg"/')
    CAST2=$(grep -o ^"Stars.*<" moviedata | sed -e "s/Stars/Cast/" -e "s/<//")
    GENRE2=$(grep ^Genre moviedata | sed -e 's/Genre: //' -e "s/<br.*//")
    if grep -qi 'documentary' <<< "$GENRE"; then continue; fi	#skip documentaries
    LINKS2=$(grep ^"<span style=\"font-family.*http.*a>" moviedata | sed -e "s/.*<a/<a/; s/a>.*/a>/; s/CLICK HERE FOR SUBTITLES /Subtitles/")
    export IMG2 CAST2 GENRE2 LINKS2
}

GET_UPDATE(){
    #function for when a post exists on turbodl
    if grep -qE "$OUTPUT2" 'movie list.txt'; then
        OUTPUT3=$(sed "s/ /%20/g" <<< "$OUTPUT2")
        LINKS3=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s -X GET "https://turbodl.xyz/wp-json/wp/v2/posts?search=$OUTPUT3&per_page=1" | jq -r '.[].content.rendered' | grep -o '<a href.*' | sed 's/<br \/>//g')
        if grep -q 'http' <<< "$LINKS3"; then
            LINKS4=$(sed "/CLICK HERE FOR SUBTITLES/d" <<< "$LINKS")
            MD5_1=$(md5sum <<< "$LINKS3")
            MD5_2=$(md5sum <<< "$LINKS4")
            if [ "$MD5_1" == "$MD5_2" ]; then
                echo "$OUTPUT   --> already posted" >> 'today.txt'
                CONTINUE='YES'; export CONTINUE
            else
                TITLE2="$TITLE [UPDATED]"
                echo "$TITLE2" >> 'today.txt'
            fi
        fi
    elif grep -q "$A" 'movie list.txt'; then
        AA=$(sed "s/ /%20/g" <<< "$A")
        LINKS3=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s -X GET "https://turbodl.xyz/wp-json/wp/v2/posts?search=$AA&per_page=1" | jq -r '.[].content.rendered' | grep -o '<a href.*' | sed 's/<br \/>//g')
        if grep -q 'http' <<< "$LINKS3"; then
            LINKS4=$(sed "/CLICK HERE FOR SUBTITLES/d" <<< "$LINKS")
            MD5_1=$(md5sum <<< "$LINKS3")
            MD5_2=$(md5sum <<< "$LINKS4")
            if [ "$MD5_1" == "$MD5_2" ]; then
                echo "$OUTPUT   --> already posted" >> 'today.txt'
                CONTINUE='YES'; export CONTINUE
            else
                TITLE2="$TITLE [UPDATED]"
                echo "$TITLE2" >> 'today.txt'
            fi
        fi
    fi
}

COUNT=1; COUNT1=0
while true; do
    curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s -o file.x -X GET "https://turbodl.xyz/wp-json/wp/v2/posts?page=$COUNT&per_page=100"
    if grep -q 'rest_post_invalid_page_number' file.x; then break; fi
    while [ $COUNT1 -lt 100 ]; do
        title=$(cat file.x | jq -r ".[$COUNT1].title.rendered" | sed -e "s/&#8211;/-/g; s/&#8217;/'/g; s/&#038;/\&/g; s/&#8216;/'/g; s/&#822[0-1];/\"/g; s/&amp;/\&/g")
        if [ "$title" == null ]; then break; fi
        grep -q "$title" 'movie list.txt' || echo "$title" >> 'movie list.txt'
        COUNT1=$((COUNT1+1))
    done
    break #COUNT1=0; COUNT=$((COUNT+1))
done

curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s -o data "https://lightdlmovies.blogspot.com/search/label/MOVIES"
grep ^'<a href=.*html.*title=.*</a>' data | sed -e "s/'>.*//; s/.*title='//; s/<\/a>//" > output
grep ^'<a href=.*html.*title=.*</a>' data | sed "s/'>.*//" > output2
echo -e ""$(date)"\\n--------------------------------" > 'today.txt'

if [ "$USER" != persie ]; then
    exec 3>&1 4>&2
    trap 'exec 2>&4 1>&3' 0 1 2 3
    exec 1>logs.txt 2>&1
fi
set -ex

while IFS= read -r OUTPUT; do	#loop through movie titles in output file
    echo -e "\\n$OUTPUT\\n------------------------------"
    if [ -e moviedata ]; then rm moviedata; fi
    OUTPUT=$(grep "$OUTPUT" output | sed -e 's/  $//; s/ $//')
    YEAR=$(grep -oE '[0-9][0-9][0-9][0-9]$' <<< "$OUTPUT" || echo 'null')
    if grep -q 'null' <<< "$YEAR"; then echo "$OUTPUT   --> year not found" >> 'today.txt'; continue; fi
    OUTPUT2=$(sed 's/[ -.][0-9][0-9][0-9][0-9]$//' <<< "$OUTPUT")
    OMDB_NAME=$(sed "s/ /%20/g" <<< "$OUTPUT2")		#format current title by replacing spaces with %20 to work with API's

    if grep -qo '[0-9][0-9][0-9][0-9]' <<< $YEAR; then
        curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s -H "Accept: application/json" -H "Content-Type: application/json" "http://www.omdbapi.com/?t=$OMDB_NAME&y=$YEAR&type=movie&plot=short&apikey=7759dbc7" | jq "." > "info" 2> /dev/null	#OMDB API to get details of movie
    else
        curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s -H "Accept: application/json" -H "Content-Type: application/json" "http://www.omdbapi.com/?t=$OMDB_NAME&type=movie&plot=short&apikey=7759dbc7" | jq "." > "info" 2> /dev/null
    fi

    if grep -qE '("Response": "False"|"Error": "Movie not found!")' info; then
        curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s --header "Content-Type: application/json" --header "trakt-api-version: 2" --header "trakt-api-key: 64ba02e985f18ec3a00186209b3605cfbbeedf9890898e3a06b8e020111e8194" "https://api.trakt.tv/search/movie?query=$OMDB_NAME" | jq "." > 'info'  2> /dev/null		#trakttv API, runs when OMDB API fails to get details because of improper title format
        C=0
        while true; do
            T=$(cat 'info' | jq -r ".[$C].movie.title")
            if [ "$T" == null ]; then break; fi
            Y=$(cat 'info' | jq -r ".[$C].movie.year")
            if [ "$Y" == $YEAR ]; then
                IMDB_ID=$(cat 'info' | jq -r ".[$C].movie.ids.imdb")
                curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s -H "Accept: application/json" -H "Content-Type: application/json" "http://www.omdbapi.com/?i=$IMDB_ID&plot=short&apikey=7759dbc7" | jq "." > "info" 2> /dev/null	#OMDB API to get movie details with imdb ID when finding with name fails
                if grep -qE '("Response": "False"|"Error": "Movie not found!")' info; then
                    T="null"
                    break
                fi
                break
            else
                C=$((C+1))
            fi
        done
        if [ "$T" == null ]; then
            DL_MOVIEDATA
            if grep -qiE "(h.*d.*cm).*mkv" <<< "$LINKS2"; then      #check for CAM links
                echo "$OUTPUT   --> CAM" >> 'today.txt'
                continue
            fi
            echo -e "<div style=\"text-align: center;\">\\n[ NO DESCRIPTION ]\\n\\nIMDB Rating: [ NULL ]\\nCast: $CAST2\\nGenre: [ $GENRE2 ]\\n\\n$LINKS2\\n</div>\\n\\nTags: [ $GENRE2, $YEAR ]" > errors/"$OUTPUT"	#place everything in errors directory because it's incomplete
            echo "$OUTPUT   --> incomplete details" >> 'today.txt'
            rm moviedata
            continue
        fi
    fi

    #execute if OMDB API is successful
    GENRE=$(grep "Genre" 'info' | sed -e 's/.*: "//' -e 's/",//')
    if grep -q 'N/A' <<< "$GENRE"; then DL_MOVIEDATA && GENRE="$GENRE2"; fi		#alternative to get genre if genre is N/A
    if grep -qi 'documentary' <<< "$GENRE"; then echo "$OUTPUT   --> documentary" >> 'today.txt'; continue; fi	#skip documentaries

    A=$(grep "Title" 'info' | sed -e 's/.*: "//' -e 's/",//')
    B=$(grep "Year.*:" 'info' | sed -e 's/.*: "//' -e 's/",//')
    TITLE="$A ($B)"		#format title and year
    PLOT=$(grep "Plot" 'info' | sed -e 's/.*: "//' -e 's/",//')
    CAST=$(grep "Actors" 'info' | sed -e 's/.*: "//' -e 's/",//')
    if grep -q 'N/A' <<< "$CAST"; then DL_MOVIEDATA && CAST=$(sed 's/Cast: //' <<< "$CAST2"); fi	#alternative to get cast if cast is N/A
    LINKS=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s $(grep "$OUTPUT" output2 | grep -o http.*html) | grep ^"<span style=\"font-family.*http.*a>" | sed "s/.*<a/<a/; s/a>.*/a>/; s/CLICK HERE FOR SUBTITLES /Subtitles/")
    if grep -qiE "(h.*d.*cm).*mkv" <<< "$LINKS"; then      #check for CAM links
        echo "$OUTPUT   --> CAM" >> 'today.txt'
        continue
    fi
    RATING=$(grep "imdbRating" 'info' | sed -e 's/.*: "//' -e 's/",//')
    if [ "$RATING" != 'N/A' ]; then
        RATE=$(sed 's/\.//' <<< "$RATING")
        if [ "$RATE" -lt 55 ]; then echo "$OUTPUT   --> rating: $RATING" >> 'today.txt'; continue; fi	#skip movie if rating is below 5.5
    else
        echo "$OUTPUT   --> rating: $RATING" >> 'today.txt'
    fi

    CHECK=$(echo -e "$A\\n$B\\n$RATING\\n$GENRE" | grep -o 'N/A' || echo 'A/N')
    if grep -q 'N/A' <<< "$CHECK"; then
        echo -e "<div style=\"text-align: center;\">\\n$PLOT\\n\\nIMDB Rating: $RATING\\nCast: $CAST\\nGenre: $GENRE\\n\\n$LINKS\\n</div>\\n\\nTags: $GENRE, $B" > errors/"$OUTPUT"
        continue
    else
        if grep -qE "($A|$OUTPUT2|$TITLE)" 'movie list.txt'; then
            GET_UPDATE; if [ "$CONTINUE" ]; then unset CONTINUE; continue; fi
        fi
        IMG=$(grep "Poster" 'info' | sed -e 's/.*: "//' -e 's/",//')
        if grep -q 'N/A' <<< "$IMG"; then DL_MOVIEDATA && IMG="$IMG2"; fi	#alternative to get image URL if image URL is N/A
        curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s "$IMG" -o movies/"$OUTPUT".jpg		#download img

        #check img dimension size
        W=$(identify -format "%w" movies/"$OUTPUT".jpg)> /dev/null
        H=$(identify -format "%h" movies/"$OUTPUT".jpg)> /dev/null
        if [ $W -gt 330 ] || [ $W -lt 270 ]; then       #width size
            mv movies/"$OUTPUT".jpg errors/"$OUTPUT".jpg
            echo "$OUTPUT   --> img width problem" >> 'today.txt'
            echo -e "<div style=\"text-align: center;\">\\n$PLOT\\n\\nIMDB Rating: $RATING\\nCast: $CAST\\nGenre: $GENRE\\n\\n$LINKS\\n</div>\\n\\nTags: $GENRE, $B" > errors/"$OUTPUT"
            continue
        elif [ $H -gt 480 ] || [ $H -lt 400 ]; then     #height size
            mv movies/"$OUTPUT".jpg errors/"$OUTPUT".jpg
            echo "$OUTPUT   --> img height problem" >> 'today.txt'
            echo -e "<div style=\"text-align: center;\">\\n$PLOT\\n\\nIMDB Rating: $RATING\\nCast: $CAST\\nGenre: $GENRE\\n\\n$LINKS\\n</div>\\n\\nTags: $GENRE, $B" > errors/"$OUTPUT"
            continue
        else
            if ! grep -qE "($A|$OUTPUT2|$TITLE)" 'movie list.txt'; then
                sed -i "1s/^/$TITLE | $OUTPUT2\\n/" 'movie list.txt'
            fi
            if [ "$TITLE2" ]; then
                echo "$TITLE2" >> 'today.txt'
                echo "$TITLE2 #$OUTPUT" >> 'titles.txt'
            else
                echo "$TITLE" >> 'today.txt'
                echo "$TITLE #$OUTPUT" >> titles.txt
            fi
            echo -e "<div style=\"text-align: center;\">\\n$PLOT\\n\\nIMDB Rating: $RATING\\nCast: $CAST\\nGenre: $GENRE\\n\\n$LINKS\\n</div>\\n\\nTags: $GENRE, $B" > movies/"$OUTPUT"
        fi
    fi
done < output	#end loop

if [ "$USER" != persie ]; then
    echo -e "\\n---sorting randomly---"
    SORTED_POSTS=$(cat titles.txt | sort -Rr)
    while IFS= read -r SORTED; do
        E=$(grep -o '#.*' <<< "$SORTED" | sed 's/#//')
        F=$(sed 's/ #.*//' <<< "$SORTED")
        echo | mutt -s "$F" -i movies/"$E" -a movies/"$E".jpg -- Ud37asAUd8a7@turbodl.xyz
    done <<< "$SORTED_POSTS"
    #mail to
    if [ -z "$(ls -A errors)" ]; then
        echo | mutt -s 'turbodlbot' -i 'today.txt' -- persie@turbodl.xyz 'info@turbodl.xyz'
    else
        echo | mutt -s 'turbodlbot' -i 'today.txt' -a errors/* -- persie@turbodl.xyz 'info@turbodl.xyz'
    fi
    echo | mutt -s 'turbodlbot log' -i titles.txt -a logs.txt 'movie list.txt' -- persie@turbodl.xyz
fi
