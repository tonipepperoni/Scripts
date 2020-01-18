#!/bin/bash
#####################################################################################################
#                                     Lidarr Automated Downloader                                   #
#                                    (Powered by: Deezloader Remix)                                 #
#                                       Credit: RandomNinjaAtk                                      #
#####################################################################################################
#                                           Script Start                                            #
#####################################################################################################

source ./config

tempalbumfile="temp-archive-album"
temptrackfile="temp-archive-track"
tempartistjson="artistinfo.json"
tempalbumlistjson="temp-albumlistdata.json"
tempalbumjson="albuminfo.json"
artistalbumlistjson="discography.json"

ArtistsLidarrReq(){
	wantit=$(curl -s --header "X-Api-Key:"${LidarrApiKey} --request GET  "$LidarrUrl/api/v1/Artist/")
	TotalLidArtistNames=$(echo "${wantit}"|jq -r '.[].sortName' | wc -l)
	MBArtistID="$(echo "${wantit}" | jq -r ".[$i].foreignArtistId")"
	for url in $MBArtistID[@]; do
		LidArtistPath="$(echo "${wantit}" | jq -r ".[] | select(.foreignArtistId==\"${url}\") | .path")"
		LidArtistID="$(echo "${wantit}" | jq -r ".[] | select(.foreignArtistId==\"${url}\") | .id")"
		LidArtistNameCap="$(echo "${wantit}" | jq -r ".[] | select(.foreignArtistId==\"${url}\") | .artistName")"
		mbjson=$(curl -s "http://musicbrainz.org/ws/2/artist/${url}?inc=url-rels&fmt=json")
		deezerartisturl=$(echo "$mbjson" | jq -r '.relations | .[] | .url | select(.resource | contains("deezer")) | .resource' | head -n 1)
		DeezerArtistID=$(printf -- "%s" "${deezerartisturl##*/}")
		artistdir="$(basename "$LidArtistPath")"
		if [ "${DeezerArtistID}" = "" ]; then
			echo "Skip... musicbrainz id: $url is missing deezer link, see: \"$LidArtistPath/musicbrainzerror.log\" for more detail..."
			if [ -f "$LidArtistPath/musicbrainzerror.log" ]; then
				rm "$LidArtistPath/musicbrainzerror.log"
			fi			
			echo "Update Musicbrainz Relationship Page: https://musicbrainz.org/artist/${MBArtistID}/relationships for \"${LidArtistNameCap}\" with Deezer Artist Link" >> "$LidArtistPath/musicbrainzerror.log"
		else
			lidarrartists
			
			LidarrProcessIt=$(curl -s $LidarrUrl/api/v1/command -X POST -d "{\"name\": \"RefreshArtist\", \"artistID\": \"${LidArtistID}\"}" --header "X-Api-Key:${LidarrApiKey}" );
			echo "Notified Lidarr to scan ${LidArtistNameCap}"
		fi
	done
}

if [ "$quality" = flac ]; then
	dlquality="flac"
elif [ "$quality" = mp3 ]; then
	dlquality="320"
elif [ "$quality" = alac ]; then
	dlquality="flac"
	targetformat="ALAC"
elif [ "$quality" = opus ]; then
	dlquality="flac"
	targetformat="OPUS"
elif [ "$quality" = aac ]; then
	dlquality="flac"
	targetformat="AAC"
fi

AlbumDL () {
	check=1
	error=0
	trackdlfallback=0
	if [ "$downloadmethod" = "album" ]; then
		if curl -s --request GET "$deezloaderurl/api/download/?url=$albumurl&quality=$dlquality" >/dev/null; then
			echo "Download Timeout: $albumtimeoutdisplay"
			echo "Downloading $tracktotal Tracks..."
			sleep $dlcheck
			let j=0
			while [[ "$check" -le 1 ]]; do
				let j++
				if curl -s --request GET "$deezloaderurl/api/queue/" | grep "length\":0,\"items\":\[\]" >/dev/null; then
					check=2
				else
					sleep 1s
					if [ "$j" = "$albumtimeout" ]; then
						dlid=$(curl -s --request GET "http://192.168.1.10:1730/api/queue/" | jq -r ".items | .[] | .queueId")
						if curl -s --request GET "$deezloaderurl/api/canceldownload/?queueId=$dlid" >/dev/null; then
							echo "Error downloading $albumname ($dlquality), retrying...via track method "
							trackdlfallback=1
							error=1
						fi
					fi
				fi
			done
			if find "$downloaddir" -iname "*.flac" | read; then
				fallbackqualitytext="FLAC"
			elif find "$downloaddir" -iname "*.mp3" | read; then
				fallbackqualitytext="MP3"
			fi
			if [ $error = 1 ]; then
				rm -rf "$downloaddir"/*
				echo "$artistname :: $albumname :: $fallbackqualitytext :: Fallback to track download method" >> "download-album-error.log"
			else
				echo "Downloaded Album: $albumname (Format: $fallbackqualitytext; Length: $albumdurationdisplay)"
				Verify
			fi
		else
			echo "Error sending download to Deezloader-Remix (Attempt 1)"
			trackdlfallback=1
		fi
	else
		trackdlfallback=1
	fi
}

DownloadURL () {
	check=1
	error=0
	retry=0
	fallback=0
	fallbackbackup=0
	fallbackquality="$dlquality"
	if curl -s --request GET "$deezloaderurl/api/download/?url=$trackurl&quality=$dlquality" >/dev/null; then
		sleep $dlcheck
		let j=0
		while [[ "$check" -le 1 ]]; do
			let j++
			if curl -s --request GET "$deezloaderurl/api/queue/" | grep "length\":0,\"items\":\[\]" >/dev/null; then
				check=2
			else
				sleep 1s
				retry=0
				if [ "$j" = "$tracktimeout" ]; then
					dlid=$(curl -s --request GET "http://192.168.1.10:1730/api/queue/" | jq -r ".items | .[] | .queueId")
					if curl -s --request GET "$deezloaderurl/api/canceldownload/?queueId=$dlid" >/dev/null; then
						echo "Error downloading track $tracknumber: $trackname ($dlquality), retrying...download"
						retry=1
						find "$downloaddir" -type f -iname "*.flac" -newer "$temptrackfile" -delete
						find "$downloaddir" -type f -iname "*.mp3" -newer "$temptrackfile" -delete
					fi
				fi
			fi
		done
	else
	    echo "Error sending download to Deezloader-Remix (Attempt 2)"
	fi
	if [ $retry = 1 ]; then
		if curl -s --request GET "$deezloaderurl/api/download/?url=$trackurl&quality=$dlquality" >/dev/null; then
			sleep $dlcheck
			let k=0
			while [[ "$retry" -le 1 ]]; do
				let k++
				if curl -s --request GET "$deezloaderurl/api/queue/" | grep "length\":0,\"items\":\[\]" >/dev/null; then
					retry=2
				else
					sleep 1s
					fallback=0
					if [ "$k" = "$trackfallbacktimout" ]; then
						dlid=$(curl -s --request GET "http://192.168.1.10:1730/api/queue/" | jq -r ".items | .[] | .queueId")
						if curl -s --request GET "$deezloaderurl/api/canceldownload/?queueId=$dlid" >/dev/null; then
							echo "Error downloading track $tracknumber: $trackname ($dlquality), retrying...as mp3 320"
							fallback=1
							find "$downloaddir" -type f -iname "*.flac" -newer "$temptrackfile" -delete
							find "$downloaddir" -type f -iname "*.mp3" -newer "$temptrackfile" -delete
						fi
					fi
				fi
			done
		else
			echo "Error sending download to Deezloader-Remix (Attempt 3)"
		fi
	fi
	if [ "$enablefallback" = true ]; then
		if [ $fallback = 1 ]; then
			if [ "$dlquality" = flac ]; then
				fallbackquality="320"
			elif [ "$dlquality" = 320 ]; then
				fallbackquality="128"
			fi
			if curl -s --request GET "$deezloaderurl/api/download/?url=$trackurl&quality=$fallbackquality" >/dev/null; then
				sleep $dlcheck
				let l=0
				while [[ "$fallback" -le 1 ]]; do
					let l++
					if curl -s --request GET "$deezloaderurl/api/queue/" | grep "length\":0,\"items\":\[\]" >/dev/null; then
						fallback=2
					else
						sleep 1s
						if [ "$l" = $tracktimeout ]; then
							dlid=$(curl -s --request GET "http://192.168.1.10:1730/api/queue/" | jq -r ".items | .[] | .queueId")
							if curl -s --request GET "$deezloaderurl/api/canceldownload/?queueId=$dlid" >/dev/null; then
								if [ "$fallbackquality" = 128 ]; then
									echo "Error downloading track $tracknumber: $trackname (mp3 128), skipping..."
									error=1
								else
									echo "Error downloading track $tracknumber: $trackname (mp3 320), retrying...as mp3 128"
									fallbackbackup=1
								fi
								find "$downloaddir" -type f -iname "*.mp3" -newer "$temptrackfile" -delete
							fi
						fi
					fi
				done
			else
				echo "Error sending download to Deezloader-Remix (Attempt 4)"
			fi
		fi
		if [ $fallbackbackup = 1 ]; then
			fallbackquality="128"
			if curl -s --request GET "$deezloaderurl/api/download/?url=$trackurl&quality=$fallbackquality" >/dev/null; then
				sleep $dlcheck
				let l=0
				while [[ "$fallbackbackup" -le 1 ]]; do
					let l++
					if curl -s --request GET "$deezloaderurl/api/queue/" | grep "length\":0,\"items\":\[\]" >/dev/null; then
						fallbackbackup=2
					else
						sleep 1s
						if [ "$l" = $trackfallbacktimout ]; then
							dlid=$(curl -s --request GET "http://192.168.1.10:1730/api/queue/" | jq -r ".items | .[] | .queueId")
							if curl -s --request GET "$deezloaderurl/api/canceldownload/?queueId=$dlid" >/dev/null; then
								echo "Error downloading track $tracknumber: $trackname (mp3 128), skipping..."
								error=1
								find "$downloaddir" -type f -iname "*.mp3" -newer "$temptrackfile" -delete
							fi
						fi
					fi
				done
			else
				echo "Error sending download to Deezloader-Remix (Attempt 5)"
			fi
		fi
	else
		echo "Error downloading track $tracknumber: $trackname ($dlquality), skipping..."
		error=1
	fi

	if find "$downloaddir" -iname "*.flac" -newer "$temptrackfile" | read; then
		fallbackqualitytext="FLAC"
	elif find "$downloaddir" -iname "*.mp3" -newer "$temptrackfile" | read; then
		fallbackqualitytext="MP3"
	fi
	if [ $error = 1 ]; then
		echo "$artistname :: $albumname :: $fallbackqualitytext :: $trackname (${trackid[$track]})" >> "download-track-error.log"
	else
		echo "Download Track $tracknumber of $tracktotal: $trackname (Format: $fallbackqualitytext; Length: $trackdurationdisplay)"
		Verify
	fi
}

Convert () {
	if [ "${quality}" = opus ]; then
		if [ -x "$(command -v opusenc)" ]; then
			if find "${downloaddir}/" -name "*.flac" | read; then
				echo "Converting: $converttrackcount Tracks (Target Format: $targetformat)"
				for fname in "${downloaddir}"/*.flac; do
					filename="$(basename "${fname%.flac}")"
					if opusenc --bitrate 128 --vbr --music "$fname" "${fname%.flac}.opus" 2> /dev/null; then
						echo "Converted: $filename"
						if [ -f "${fname%.flac}.opus" ]; then
							rm "$fname"
						fi
					else
						echo "Conversion failed: $filename, performing cleanup..."
						if [ -f "${fname%.flac}.opus" ]; then
							rm "${fname%.flac}.opus"
						fi
						if [ ! -f "conversion-failure.log" ]; then
							touch "conversion-failure.log"
							chmod 0666 "conversion-failure.log"
						fi
						echo "$artistname :: $albumname :: $quality :: $filename.flac" >> "conversion-failure.log"
					fi
				done
			fi
		else
			echo "ERROR: opus-tools not installed, please install opus-tools to use this conversion feature"
			sleep 5s
		fi
	fi
	if [ "${quality}" = aac ]; then
		if [ -x "$(command -v ffmpeg)" ]; then
			if find "${downloaddir}/" -name "*.flac" | read; then
				echo "Converting: $converttrackcount Tracks (Target Format: $targetformat)"
				for fname in "${downloaddir}"/*.flac; do
					filename="$(basename "${fname%.flac}")"
					if ffmpeg -loglevel warning -hide_banner -nostats -i "$fname" -n -vn -acodec aac -ab 320k -movflags faststart "${fname%.flac}.m4a"; then
						echo "Converted: $filename"
						if [ -f "${fname%.flac}.m4a" ]; then
							rm "$fname"
						fi
					else
						echo "Conversion failed ($quality): $filename, performing cleanup..."
						if [ -f "${fname%.flac}.m4a" ]; then
							rm "${fname%.flac}.m4a"
						fi
						if [ ! -f "conversion-failure.log" ]; then
							touch "conversion-failure.log"
							chmod 0666 "conversion-failure.log"
						fi
						echo "$artistname :: $albumname :: $quality :: $filename.flac" >> "conversion-failure.log"
					fi
				done
			fi
		else
			echo "ERROR: ffmpeg not installed, please install ffmpeg to use this conversion feature"
			sleep 5s
		fi
	fi
	if [ "${quality}" = alac ]; then
		if [ -x "$(command -v ffmpeg)" ]; then
			if find "${downloaddir}/" -name "*.flac" | read; then
				echo "Converting: $converttrackcount Tracks (Target Format: $targetformat)"
				for fname in "${downloaddir}"/*.flac; do
					filename="$(basename "${fname%.flac}")"
					if ffmpeg -loglevel warning -hide_banner -nostats -i "$fname" -n -vn -acodec alac -movflags faststart "${fname%.flac}.m4a"; then
						echo "Converted: $filename"
						if [ -f "${fname%.flac}.m4a" ]; then
							rm "$fname"
						fi
					else
						echo "Conversion failed: $filename, performing cleanup..."
						if [ -f "${fname%.flac}.m4a" ]; then
							rm "${fname%.flac}.m4a"
						fi
						if [ ! -f "conversion-failure.log" ]; then
							touch "conversion-failure.log"
							chmod 0666 "conversion-failure.log"
						fi
						echo "$artistname :: $albumname :: $quality :: $filename.flac" >> "conversion-failure.log"
					fi
				done
			fi
		else
			echo "ERROR: ffmpeg not installed, please install ffmpeg to use this conversion feature"
			sleep 5s
		fi
	fi
}

Verify () {
	if [ $trackdlfallback = 0 ]; then
		if find "$downloaddir" -iname "*.flac" | read; then
			if ! [ -x "$(command -v flac)" ]; then
				echo "ERROR: FLAC verification utility not installed (ubuntu: apt-get install -y flac)"
			else
				for fname in "${downloaddir}"/*.flac; do
					filename="$(basename "$fname")"
					if flac -t --totally-silent "$fname"; then
						echo "Verified Track: $filename"
					else
						rm -rf "$downloaddir"/*
						trackdlfallback=1
					fi
				done
			fi
		fi
		if find "$downloaddir" -iname "*.mp3" | read; then
			if ! [ -x "$(command -v mp3val)" ]; then
				echo "MP3VAL verification utility not installed (ubuntu: apt-get install -y mp3val)"
			else
				for fname in "${downloaddir}"/*.mp3; do
					filename="$(basename "$fname")"
					if mp3val -f -nb "$fname" > /dev/null; then
						echo "Verified Track: $filename"
					fi
				done
			fi
		fi
	elif [ $trackdlfallback = 1 ]; then
		if ! [ -x "$(command -v flac)" ]; then
			echo "ERROR: FLAC verification utility not installed (ubuntu: apt-get install -y flac)"
		else
			if find "$downloaddir" -iname "*.flac" -newer "$temptrackfile" | read; then
				find "$downloaddir" -iname "*.flac" -newer "$temptrackfile" -print0 | while IFS= read -r -d '' file; do
					filename="$(basename "$file")"
					if flac -t --totally-silent "$file"; then
						echo "Verified Track $tracknumber of $tracktotal: $trackname (Format: $fallbackqualitytext; Length: $trackdurationdisplay)"
					else
						rm "$file"
						if [ "$enablefallback" = true ]; then
							echo "Track Verification Error: \"$trackname\" deleted...retrying as MP3"
							origdlquality="$dlquality"
							dlquality="320"
							DownloadURL
							dlquality="$origdlquality"
						else
							echo "Verification Error: \"$trackname\" deleted..."
							echo "Fallback quality disabled, skipping..."
							echo "$artistname :: $albumname :: $fallbackqualitytext :: $trackname (${trackid[$track]})" >> "download-track-error.log"
						fi
					fi
				done
			fi
		fi
		if ! [ -x "$(command -v mp3val)" ]; then
			echo "MP3VAL verification utility not installed (ubuntu: apt-get install -y mp3val)"
		else
			if find "$downloaddir" -iname "*.mp3" -newer "$temptrackfile" | read; then
				find "$downloaddir" -iname "*.mp3" -newer "$temptrackfile" -print0 | while IFS= read -r -d '' file; do
					filename="$(basename "$file")"
					if mp3val -f -nb "$file" > /dev/null; then
						echo "Verified Track $tracknumber of $tracktotal: $trackname (Format: $fallbackqualitytext; Length: $trackdurationdisplay)"
					fi
				done
			fi
		fi
	fi
}

DLArtistArtwork () {
	if [ ! -d "$fullartistpath" ]; then
		mkdir "$fullartistpath"
		chmod 0777 "$fullartistpath"
	fi
	if [ -d "$fullartistpath" ]; then
		if [ ! -f "$fullartistpath/folder.jpg"  ]; then
			echo ""
			echo "Archiving Artist Profile Picture"
			if curl -sL --fail "${artistartwork}" -o "$fullartistpath/folder.jpg"; then
				if find "$fullartistpath/folder.jpg" -type f -size -16k | read; then
					echo "ERROR: Artist artwork is smaller than \"16k\""
					rm "$fullartistpath/folder.jpg"
					echo ""
				else
					echo "Downloaded 1 profile picture"
					echo ""
				fi
			else
				echo "Error downloading artist artwork"
				echo ""
			fi
		fi
	fi

}

DLAlbumArtwork () {
	if curl -sL --fail "${albumartworkurl}" -o "$downloaddir/folder.jpg"; then
		sleep 0.1
	else
		echo "Failed downloading album cover picture..."
	fi
}

Replaygain () {
	if ! [ -x "$(command -v flac)" ]; then
		echo "ERROR: METAFLAC replaygain utility not installed (ubuntu: apt-get install -y flac)"
	elif find "$downloaddir" -name "*.flac" | read; then
		find "$downloaddir" -name "*.flac" -exec metaflac --add-replay-gain "{}" + && echo "Replaygain: $replaygaintrackcount Tracks Tagged"
	fi
}

DurationCalc () {
  local T=$1
  local D=$((T/60/60/24))
  local H=$((T/60/60%24))
  local M=$((T/60%60))
  local S=$((T%60))
  (( $D > 0 )) && printf '%d days and ' $D
  (( $H > 0 )) && printf '%d:' $H
  (( $M > 0 )) && printf '%02d:' $M
  (( $D > 0 || $H > 0 || $M > 0 )) && printf ''
  printf '%02ds\n' $S
}

sanitize() {
   local s="${1?need a string}" # receive input in first argument
   s="${s//[^[:alnum:]]/-}"     # replace all non-alnum characters to -
   s="${s//+(-)/-}"             # convert multiple - to single -
   s="${s/#-}"                  # remove - from start
   s="${s/%-}"                  # remove - from end
   echo "${s,,}"                # convert to lowercase
}

if [ "${LyricType}" = explicit ]; then
	LyricDLType="Explicit"
elif [ "${LyricType}" = clean ]; then
	LyricDLType="Clean"
else
	LyricDLType="Explicit Preferred"
fi

ConfigSettings () {
	echo "START DEEZER ARCHIVING"
	echo ""
	echo "Global Settings"
	echo "Download Client: $deezloaderurl"
	echo "Download Directory: $downloaddir"
	echo "Library Directory: $library"
	echo "Download Quality: $quality"
	echo "Download Lyric Type: $LyricDLType"
	echo "Total Artists To Process: $TotalLidArtistNames"
	echo ""
	echo "Begin archive process..."
	sleep 5s
}

if [ ! -d "$downloaddir" ];	then
	mkdir -p "$downloaddir"
	chmod 0777 "$downloaddir"
fi

lidarrartists () {

	ConfigSettings

	if [ -f "$tempartistjson" ]; then
		rm "$tempartistjson"
	fi
	if [ -f "$tempalbumlistjson" ]; then
		rm "$tempalbumlistjson"
	fi
	if [ -f "$tempalbumjson"  ]; then
		rm "$tempalbumjson"
	fi
	if [ -f "$temptrackfile" ]; then
		rm "$temptrackfile"
	fi
	rm -rf "$downloaddir"/*
	if curl -sL --fail "https://api.deezer.com/artist/$DeezerArtistID" -o "$tempartistjson"; then
		artistartwork=($(cat "$tempartistjson" | jq -r '.picture_xl'))
		artistname="$(cat "$tempartistjson" | jq -r '.name')"
		artistid="$(cat "$tempartistjson" | jq -r '.id')"
		sanatizedartistname="$(echo "$artistname" | sed -e 's/[\\/:\*\?"<>\|\x01-\x1F\x7F]//g' -e 's/^\(nul\|prn\|con\|lpt[0-9]\|com[0-9]\|aux\)\(\.\|$\)//i' -e 's/^\.*$//' -e 's/^$/NONAME/')"
		shortartistpath="$artistname ($artistid)"
		fullartistpath="$LidArtistPath"
		if [ "$artistname" == null ]; then
			echo ""
			echo "Error no artist returned with Deezer Artist ID \"$artistid\""
		else
			if curl -sL --fail "https://api.deezer.com/artist/$artistid/albums&limit=1000" -o "$tempalbumlistjson"; then
				if [ "$LyricType" = explicit ]; then
					LyricDLType=" Explicit"
					albumlist=($(cat "$tempalbumlistjson" | jq -r ".data | .[]| select(.explicit_lyrics==true)| .id"))
					totalnumberalbumlist=($(cat "$tempalbumlistjson" | jq -r ".data | .[]| select(.explicit_lyrics==true)| .id" | wc -l))
				elif [ "$LyricType" = clean ]; then
					LyricDLType=" Clean"
					albumlist=($(cat "$tempalbumlistjson" | jq -r ".data | .[]| select(.explicit_lyrics==false)| .id"))
					totalnumberalbumlist=($(cat "$tempalbumlistjson" | jq -r ".data | .[]| select(.explicit_lyrics==false)| .id" | wc -l))
				else
					LyricDLType=""
					albumlist=($(cat "$tempalbumlistjson" | jq -r ".data | sort_by(.explicit_lyrics) | reverse | .[] | .id"))
					totalnumberalbumlist=($(cat "$tempalbumlistjson" | jq -r ".data | sort_by(.explicit_lyrics) | reverse | .[] | .id" | wc -l))
				fi
				if [ "$totalnumberalbumlist" = 0 ]; then
					echo ""
					echo "Archiving: $artistname ($artistid)"
					echo "ERROR: No albums found"
				else
					echo ""
					echo ""
					echo "Archiving: $artistname ($artistid)"
					echo "Searching for albums... $totalnumberalbumlist Albums found"
					for album in ${!albumlist[@]}; do
						trackdlfallback=0
						albumnumber=$(( $album + 1 ))
						albumurl="https://www.deezer.com/album/${albumlist[$album]}"
						albumname=$(cat "$tempalbumlistjson" | jq -r ".data | .[]| select(.id=="${albumlist[$album]}") | .title")
						albumnamesanatized="$(echo "$albumname" | sed -e 's/[\\/:\*\?"<>\|\x01-\x1F\x7F]//g' -e 's/^\(nul\|prn\|con\|lpt[0-9]\|com[0-9]\|aux\)\(\.\|$\)//i' -e 's/^\.*$//' -e 's/^$/NONAME/')"
						sanatizedfuncalbumname="${albumnamesanatized,,}"

						if [ -f "$fullartistpath/$artistalbumlistjson" ]; then
							if cat "$fullartistpath/$artistalbumlistjson" | grep "${albumlist[$album]}" | read; then
								echo "Previously Downloaded \"$albumname\", skipping..."
								continue
							fi
						fi
						if curl -sL --fail "https://api.deezer.com/album/${albumlist[$album]}" -o "$tempalbumjson"; then
							tracktotal=$(cat "$tempalbumjson" | jq -r ".nb_tracks")
							albumdartistid=$(cat "$tempalbumjson" | jq -r ".artist | .id")
							albumlyrictype="$(cat "$tempalbumjson" | jq -r ".explicit_lyrics")"
							albumartworkurl="$(cat "$tempalbumjson" | jq -r ".cover_xl")"
							albumdate="$(cat "$tempalbumjson" | jq -r ".release_date")"
							albumyear=$(echo ${albumdate::4})
							albumtype="$(cat "$tempalbumjson" | jq -r ".record_type")"
							albumtypecap="${albumtype^^}"
							albumduration=$(cat "$tempalbumjson" | jq -r ".duration")
							albumdurationdisplay=$(DurationCalc $albumduration)
							albumtimeout=$(($albumduration*$albumtimeoutpercentage/100))
							albumtimeoutdisplay=$(DurationCalc $albumtimeout)
							albumfallbacktimout=$(($albumduration*2))
							if [ "$albumlyrictype" = true ]; then
								albumlyrictype="Explicit"
							elif [ "$albumlyrictype" = false ]; then
								albumlyrictype="Clean"
							fi
							libalbumfolder="$sanatizedartistname - $albumtypecap - $albumyear - $albumnamesanatized ($albumlyrictype)"
							if [ "$albumdartistid" -ne "$artistid" ]; then
								continue
							fi

							if [ -f "$fullartistpath/$artistalbumlistjson" ]; then
								if [ "$debug" = "true" ]; then
									echo ""
								fi
								arcsantitle="$(cat "$fullartistpath/$artistalbumlistjson" | jq -r ".[] | select(.sanatized_album_name==\"$sanatizedfuncalbumname\") | .sanatized_album_name")"
								if [ "$arcsantitle" = "$sanatizedfuncalbumname" ]; then
									archivealbumname="$(cat "$fullartistpath/$artistalbumlistjson" | jq -r ".[] | select(.sanatized_album_name==\"$sanatizedfuncalbumname\") | .title")"
									archivealbumlyrictype="$(cat "$fullartistpath/$artistalbumlistjson" | jq -r ".[] | select(.sanatized_album_name==\"$sanatizedfuncalbumname\") | .explicit_lyrics")"
									archivealbumtracktotal="$(cat "$fullartistpath/$artistalbumlistjson" | jq -r ".[] | select(.sanatized_album_name==\"$sanatizedfuncalbumname\") | .nb_tracks")"
									archivealbumreleasetype="$(cat "$fullartistpath/$artistalbumlistjson" | jq -r ".[] | select(.sanatized_album_name==\"$sanatizedfuncalbumname\") | .record_type")"
									archivealbumdate="$(cat "$fullartistpath/$artistalbumlistjson" | jq -r ".[] | select(.sanatized_album_name==\"$sanatizedfuncalbumname\") | .release_date")"
									archivealbumfoldername="$(cat "$fullartistpath/$artistalbumlistjson" | jq -r ".[] | select(.sanatized_album_name==\"$sanatizedfuncalbumname\") | .foldername")"
									arhcivealbumyear="$(echo ${archivealbumdate::4})"
									if [ "$archivealbumlyrictype" = true ]; then
										archivealbumlyrictype="Explicit"
									elif [ "$archivealbumlyrictype" = false ]; then
										archivealbumlyrictype="Clean"
									fi
									if [ "$debug" = "true" ]; then
										echo ""
										echo "Archive Match: $arcsantitle (Archive) | grep -x $sanatizedfuncalbumname (Incoming)"
										echo ""
										echo "Dedupe info:"
										echo "Incoming Album: $albumname"
										echo "Incoming Album: $sanatizedfuncalbumname"
										echo "Incoming Album: $tracktotal Tracks"
										echo "Incoming Album: $albumtype"										
										echo "Incoming Album: $albumlyrictype"
										echo "Incoming Album: $albumyear"
										echo "Incoming Album: $libalbumfolder"
										echo ""
										echo "Archive: $archivealbumname"
										echo "Archive: $arcsantitle"
										echo "Archive: $archivealbumtracktotal Tracks"
										echo "Archive: $archivealbumreleasetype"
										echo "Archive: $archivealbumlyrictype"
										echo "Archive: $arhcivealbumyear"
										echo "Archive: $archivealbumfoldername"
										echo ""
									fi
									if [ "$albumlyrictype" = "Explicit" ]; then
										if [ "$debug" = "true" ]; then
											echo "Dupe found $albumname :: check 1"
										fi
										if [ "$albumyear" = "$arhcivealbumyear" ]; then
											if [ "$debug" = "true" ]; then
												echo "Incoming album: $albumname has same year as existing :: check 2"
												fi
											continue
										else
											if [ "$debug" = "true" ]; then
												echo "Year does not match new: $albumyear; archive: $arhcivealbumyear :: check 3"
											fi
										fi
									fi
									if [ "$albumlyrictype" = "Clean" ]; then
										if [ "$debug" = "true" ]; then
											echo "Dupe found $albumname :: check 10"
										fi
										if [ "$archivealbumlyrictype" = "Explicit" ]; then
											if [ "$debug" = "true" ]; then
												echo "Archived album: $albumname is Explicit, Skipping... :: check 11"
											fi
											continue
										fi

										if [ "$archivealbumlyrictype" = "Clean" ]; then
											if [ "$debug" = "true" ]; then
												echo "Archive album is also clean :: check 12"
											fi
											if [ "$albumtype" = "single" ] && [ "$archivealbumreleasetype" = "single" ] && [ "$archivealbumname" != "$albumname" ]; then
												if [ "$debug" = "true" ]; then
													echo "Incoming and Archive album: $albumname are both $albumlyrictype and $archivealbumname != $albumname :: check 13"
												fi
											else
												if [ "$tracktotal" -gt "$archivealbumtracktotal" ]; then
													if [ "$debug" = "true" ]; then
														echo "Incoming album: $albumname, has more total tracks: $tracktotal vs $archivealbumtracktotal :: check 14"
													fi
													rm -rf "$fullartistpath/$archivealbumfoldername"
													sleep 0.5s
												else
													if [ "$debug" = "true" ]; then
														echo "Incoming album: $albumname, same/less total tracks: $tracktotal vs $archivealbumtracktotal :: check 15"
													fi
													continue
												fi
											fi
										fi
									fi
								fi
								if [ "$debug" = "true" ]; then
									echo ""
									sleep 3
								fi
							fi
							DLArtistArtwork
							if [[ "$albumtimeout" -le 60 ]]; then
								albumtimeout="60"
								albumfallbacktimout=$(($albumtimeout*2))
								albumtimeoutdisplay=$(DurationCalc $albumtimeout)
							fi
							if [ ! -f "$tempalbumfile" ]; then
								touch "$tempalbumfile"
							fi
							echo ""
							echo "Archiving \"$artistname\" ($artistid) in progress..."
							echo "Archiving Album: $albumname"
							echo "Album Release Year: $albumyear"
							echo "Album Release Type: $albumtype"
							echo "Album Lyric Type: $albumlyrictype"
							echo "Album Duration: $albumdurationdisplay"
							echo "Album Track Count: $tracktotal"
							AlbumDL
							if [ $trackdlfallback = 1 ]; then
								echo "Donwloading $tracktotal Tracks..."
								trackid=($(cat "$tempalbumjson" | jq -r ".tracks | .data | .[] | .id"))
								for track in ${!trackid[@]}; do
									tracknumber=$(( $track + 1 ))
									trackname=$(cat "$tempalbumjson" | jq -r ".tracks | .data | .[] | select(.id=="${trackid[$track]}") | .title")
									trackduration=$(cat "$tempalbumjson" | jq -r ".tracks | .data | .[] | select(.id=="${trackid[$track]}") | .duration")
									trackdurationdisplay=$(DurationCalc $trackduration)
									trackurl="https://www.deezer.com/track/${trackid[$track]}"
									tracktimeout=$(($trackduration*$tracktimeoutpercentage/100))
									trackfallbacktimout=$(($tracktimeout*2))
									if [[ "$tracktimeout" -le 60 ]]; then
										tracktimeout="60"
										trackfallbacktimout=$(($tracktimeout*2))
									fi
									if [ ! -f "$temptrackfile" ]; then
										touch "$temptrackfile"
									fi
									DownloadURL
									if [ -f "$temptrackfile" ]; then
										rm "$temptrackfile"
									fi
								done
							fi
							DLAlbumArtwork
							downloadedtrackcount=$(find "$downloaddir" -type f -iregex ".*/.*\.\(flac\|opus\|m4a\|mp3\)" | wc -l)
							downloadedlyriccount=$(find "$downloaddir" -type f -iname "*.lrc" | wc -l)
							downloadedalbumartcount=$(find "$downloaddir" -type f -iname "folder.*" | wc -l)
							replaygaintrackcount=$(find "$downloaddir" -type f -iname "*.flac" | wc -l)
							converttrackcount=$(find "$downloaddir" -type f -iname "*.flac" | wc -l)
							echo "Downloaded: $downloadedtrackcount Tracks"
							echo "Downloaded: $downloadedlyriccount Synced Lyrics"
							echo "Downloaded: $downloadedalbumartcount Album Cover"
							if [ "$replaygaintaggingflac" = true ]; then
								if [ "$quality" = flac ]; then
									Replaygain
								fi
							fi
							if [ "$replaygaintaggingopus" = true ]; then
								if [ "$quality" = opus ]; then
									Replaygain
								fi
							fi

							Convert

							if [ -d "$fullartistpath/$libalbumfolder" ]; then
								rm -rf "$fullartistpath/$libalbumfolder"
								sleep 0.5s
							fi
							mkdir "$fullartistpath/$libalbumfolder"
							jq ". + {\"sanatized_album_name\": \"$sanatizedfuncalbumname\"} + {\"foldername\": \"$libalbumfolder\"} + {\"artistpath\": \"$fullartistpath\"}" "$tempalbumjson" > "$fullartistpath/$libalbumfolder/$tempalbumjson"
							for file in "$downloaddir"/*; do
								mv "$file" "$fullartistpath/$libalbumfolder"/
							done

							if find "$fullartistpath/$libalbumfolder" -iname "*.flac" | read; then
								archivequality="FLAC"
							elif find "$fullartistpath/$libalbumfolder" -iname "*.mp3" | read; then
								archivequality="MP3"
							elif find "$fullartistpath/$libalbumfolder" -iname "*.opus" | read; then
								archivequality="OPUS"
							elif find "$fullartistpath/$libalbumfolder" -iname "*.m4a" | read; then
								if [ "$quality" = alac ]; then
									archivequality="ALAC"
								fi
								if [ "$quality" = aac ]; then
									archivequality="AAC"
								fi
							fi
							echo "Archiving Album: $albumname (Format: $archivequality) complete!"

							if [ -f "$tempalbumfile" ]; then
								rm "$tempalbumfile"
							fi
							rm -rf "$downloaddir"/*
							sleep 0.5
						else
							echo "Error contacting Deezer for album information"
						fi
						if [ -d "$fullartistpath" ]; then
							jq -s '.' "$fullartistpath"/*/"$tempalbumjson" > "$fullartistpath/$artistalbumlistjson"
						fi
						if [ -f "$tempalbumjson" ]; then
							rm "$tempalbumjson"
						fi
					done
				totalalbumsarchived="$(cat "$fullartistpath/$artistalbumlistjson" | jq -r ".[] | .id" |wc -l)"
				echo ""
				if [ "$totalalbumsarchived" = "$totalnumberalbumlist" ]; then
					echo "Archived $totalalbumsarchived Albums"
				else
					echo "Archived $totalalbumsarchived of $totalnumberalbumlist Albums (Some Dupes found... and removed...)"
				fi
				echo "Archiving $artistname complete!"
				echo ""
				find "$fullartistpath" -type d -exec chmod 0777 "{}" \;
				find "$fullartistpath" -type f -exec chmod 0666 "{}" \;
					if [ -f "$tempalbumlistjson"  ]; then
						rm "$tempalbumlistjson"
					fi
				fi
			else
				echo "Error contacting Deezer for artist album list information"
			fi
		fi
	else
		echo "Error contacting Deezer for artist information"
	fi
	if [ -d "$fullartistpath" ]; then
		if [ -f "$tempartistjson"  ]; then
			mv "$tempartistjson" "$fullartistpath"/
		fi
		if [ -d "$fullartistpath" ]; then
			jq -s '.' "$fullartistpath"/*/"$tempalbumjson" > "$fullartistpath/$artistalbumlistjson"
		fi
	fi
	sleep 0.5


}

ArtistsLidarrReq