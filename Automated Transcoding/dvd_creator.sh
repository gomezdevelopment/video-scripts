#/bin/sh

# 1) look for files in the /home/jordanpark/dvd_creator/ directory
# 2) run ffmpeg to convert the MP4 file to a DVD compliant video
#	NOTE: max bitrate allowed, as sermons will be less than 1 hour:
#		1 hour at 8 mpbs =~ 3.43 GB
# 3) rm original MP4
# 4) run dvdauthor to create DVD structure (dvdauthor --title -o dvd -f out.mpg) from http://www.cyberciti.biz/tips/howto-linux-create-video-dvds.html
# 5) rm MPG file
# 6) run mkisofs to create ISO file (mkisofs -dvd-video -o dvd.iso dvd/) from same URL.
# 7) clean up the rest.

#for i in /home/jordanpark/Desktop/dvd_creator/*.MP4;
#shopt -s nullglob

#cd /home/auditorium/Desktop/dvd_creator

if [ ! -e lock ];
then touch lock;
#	echo "converting: $1";
	if ffmpeg -y -i "$1" -target ntsc-dvd -b:v 8M dvd.mpg;	#a small delay...
	then
#	ffmpeg -i "$1" -c:a copy "$1.aac";
	ffmpeg -i "$1" "$1.wav";
	rm "$1";

#	mplex -f 8 -o out.mpg dvd.mpg dvd.m2a;	#unrecognizable
#
#	echo "authoring $1.mpg...";
	dvdauthor -t -c 5:00,10:00,15:00,20:00,25:00,30:00,35:00,40:00,45:00,50:00,55:00,1:00:00 dvd.mpg -o dvd;
	export VIDEO_FORMAT=ntsc;
	dvdauthor -T -o dvd;
	rm dvd.mpg;
#	
#	echo "making $1.iso ...";
	genisoimage -dvd-video -o "$1.iso" dvd/;
#	mkisofs -dvd-video -o "$1.iso" dvd/;
	rm -rf dvd/;
	fi
	rm lock;
fi
