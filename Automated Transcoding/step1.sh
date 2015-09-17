if [ ! -e lock ];
	then touch lock;
#
#	TESTING NOTES
#	Original: 4.5 MB
#	CRF 22: 490 kB
#	CRF 20: 817 kB
#	CRF 18: 1.4 MB

	if ffmpeg -y -i "$1" -movflags +faststart -vf yadif,scale=640x480,setdar=4:3,fps=30000/1001 -c:a libfdk_aac -b:a 128k -c:v libx264 -crf 20 -preset veryfast "$(basename "$1" .ts ).mp4";
		then rm "$1";
		fi
	rm lock;
fi
