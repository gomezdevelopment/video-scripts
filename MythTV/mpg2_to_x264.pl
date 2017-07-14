#!/usr/bin/perl -w
# ============================================================================
# = NAME 
# x264_transcode_high.pl
#
# = PURPOSE
# Convert mpeg2 file from myth to h264 with aac audio.
#
# = USAGE
my $usage = 'Usage:
mpg2_to_x264.pl -j %JOBID% 
mpg2_to_x264.pl -f %FILE% 
';

# ============================================================================

use strict;
use MythTV;
use XML::Simple;

# What file are we copying/transcoding?
my $file  = '';
my $jobid = -1;

# do nothing?
my $noexec = 0;

# extra console output?
my $DEBUG = 1;

# some globals
my ($chanid, $command, $query, $ref, $starttime, $showtitle, $episodetitle);
my ($seasonnumber, $episodenumber, $episodedetails);
my ($newfilename, $newstarttime);
my $xmlparser = new XML::Simple;
my $xmlstring;
# globals for stream and resolution mapping
my ($output, $videostream, $audiostreamsurround, $audiostreamstereo, $framerate);

# transcode options
my $deinterlace = "-deinterlace"; # disabled if video is found to be progressive
my $size = "hd720";
my $audiocodec = "libfdk_aac";
my $audiobitrate = "160k";
my $audiofrequency = "48000";
my $audiochannels = 6; # changed to 2 if input carries no surround audio
my $audiostream = 1.0; # default audio channel
my $ftype = "mp4";
my $nicevalue = 17; # don't hog the CPU
my $videopreset = "veryfast";
my $videocodec = "libx264";
my $videocrf = "18"; # target bitrate
my $movflags = "+faststart"; #move the moov atom to the front

my $mt = '';
my $db = '';

sub Reconnect()
{
    $mt = new MythTV();
    $db = $mt->{'dbh'};
}

# ============================================================================
sub Die($)
{
    print STDERR "@_\n";
    exit -1;
}
# ============================================================================
# Parse command-line arguments, check there is something to do:
#
if ( ! @ARGV )
{   Die "$usage"  }
Reconnect;

while ( @ARGV && $ARGV[0] =~ m/^-/ )
{
    my $arg = shift @ARGV;

    if ( $arg eq '-d' || $arg eq '--debug' )
    {   $DEBUG = 1  }
    elsif ( $arg eq '-n' || $arg eq '--noaction' )
    {   $noexec = 1  }
    elsif ( $arg eq '-j' || $arg eq '--jobid' )
    {   $jobid = shift @ARGV  }
    elsif ( $arg eq '-f' || $arg eq '--file' )
    {   $file = shift @ARGV  }
    else
    {
        unshift @ARGV, $arg;
        last;
    }
}

if ( ! $file && $jobid == -1 )
{
    Die "No file or job specified. $usage";
}

# ============================================================================
# If we were supplied a jobid, lookup chanid
# and starttime so that we can find the filename
#
if ( $jobid != -1 )
{
    $query = $db->prepare("SELECT chanid, starttime " .
                          "FROM jobqueue WHERE id=$jobid;");
    $query->execute || Die "Unable to query jobqueue table";
    $ref       = $query->fetchrow_hashref;
    $chanid    = $ref->{'chanid'};
    $starttime = $ref->{'starttime'};
    $query->finish;

    if ( ! $chanid || ! $starttime )
    {   Die "Cannot find details for job $jobid"  }

    $query = $db->prepare("SELECT basename FROM recorded " .
                          "WHERE chanid=$chanid AND starttime='$starttime';");
    $query->execute || Die "Unable to query recorded table";
    ($file) = $query->fetchrow_array;
    $query->finish;

    if ( ! $file )
    {   Die "Cannot find recording for chan $chanid, starttime $starttime"  }

    if ( $DEBUG )
    {
        print "Job $jobid refers to recording chanid=$chanid,",
              " starttime=$starttime\n"
    }
}
else
{
    if ( $file =~ m/(\d+)_(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/ )
    {   $chanid = $1, $starttime = "$2-$3-$4 $5:$6:$7"  }
    else
    {
        print "File $file has a strange name. Searching in recorded table\n";
        $query = $db->prepare("SELECT chanid, starttime " .
                              "FROM recorded WHERE basename='$file';");
        $query->execute || Die "Unable to query recorded table";
        ($chanid,$starttime) = $query->fetchrow_array;
        $query->finish;

        if ( ! $chanid || ! $starttime )
        {   Die "Cannot find details for filename $file"  }
    }
}


# A commonly used SQL row selector:
my $whereChanAndStarttime = "WHERE chanid=$chanid AND starttime='$starttime'";

# ============================================================================
# Find the directory that contains the recordings, check the file exists
#
my $dir  = undef;
my $dirs = $mt->{'video_dirs'};

foreach my $d ( @$dirs )
{
	if ( ! -e $d )
	{   Die "Cannot find directory $dir that contains recordings"  }

	if ( -e "$d/$file" )
	{
		$dir = $d;
		last
	}
	else
	{   print "$d/$file does not exist\n"   }
}

if ( ! $dir )
{   Die "Cannot find recording"  }

# ============================================================================
# Get ffmpegs info
#

$audiostreamstereo   = "";
$audiostreamsurround = "";
$command = "ffmpeg -i $dir/$file ";
open(FF_info, "$command 2>&1 |");
while ( defined(my $line = <FF_info>) ) {
	chomp($line);
	if ( $line =~ /^\s*Stream.*#(\S\.\S).*:\sVideo.*\s(\S*)\stbr/ )
	{
		$framerate = $2;
		$videostream = $1;
		next;
	}
	if ( $line =~ /^\s*Stream.*#(\S\.\S).*:\sAudio.*stereo/ )
	{
		$audiostreamstereo = $1;
		next;
	}
	if ( $line =~ /^\s*Stream.*#(\S\.\S).*:\sAudio.*5.1/ )
	{
		$audiostreamsurround = $1;
		next;
	}
}
if ( $framerate <= 30.0 ) { $deinterlace = "-deinterlace" } elsif ( $framerate > 30 && $framerate <= 60 ) { $deinterlace = "" }

# ============================================================================
# First, generate a new filename,
#

$query = $db->prepare("SELECT title FROM recorded $whereChanAndStarttime;");
$query->execute || Die "Unable to query recorded table";
$showtitle = $query->fetchrow_array;
$query->finish;

$query = $db->prepare("SELECT subtitle FROM recorded $whereChanAndStarttime;");
$query->execute || Die "Unable to query recorded table";
$episodetitle = $query->fetchrow_array;
$query->finish;

if ( $episodetitle ne "" ) 
{
  $seasonnumber = "";
  $episodenumber = "";
  $xmlstring = `/usr/share/mythtv/metadata/Television/ttvdb.py -N "$showtitle" "$episodetitle"`;
  if ( $xmlstring ne "" ) {
    $episodedetails =$xmlparser->XMLin($xmlstring);
    $seasonnumber = $episodedetails->{item}->{season};
    $episodenumber = $episodedetails->{item}->{episode};
  }
}
my ($year,$month,$day,$hour,$mins,$secs) = split m/[- :]/, $starttime;
my $oldShortTime = sprintf "%04d%02d%02d",
                   $year, $month, $day;
my $iter = 0;

do {
  if ( $episodetitle eq "" || $seasonnumber eq "" || $episodenumber eq "" )
  {
    $newfilename = sprintf "%s_%s.%s.%s", $showtitle, $month, $day, $year;
  } else {
    $newfilename = sprintf "%s_S%0sE%0s_%s", $showtitle, $seasonnumber, $episodenumber, $episodetitle;
  }
  $newfilename =~ s/\;/   AND   /g;
  $newfilename =~ s/\&/   AND   /g;
  $newfilename =~ s/\s+/ /g;
  $newfilename =~ s/\s/_/g;
  $newfilename =~ s/:/_/g;
  $newfilename =~ s/__/_/g;
  $newfilename =~ s/\(//g;
  $newfilename =~ s/\)//g;
  $newfilename =~ s/'//g;
  $newfilename =~ s/\!//g;
  $newfilename =~ s/\///g;
  $newfilename =~ s/\|//g;
  if ( $iter != "0" ) 
  {  $newfilename = sprintf "%s_%d%s", $newfilename, $iter, ".mp4"  } else { $newfilename = sprintf "%s%s", $newfilename, ".mp4" }
  $iter ++;
  $secs = $secs + $iter;
  $newstarttime = sprintf "%04d-%02d-%02d %02d:%02d:%02d",
                    $year, $month, $day, $hour, $mins, $secs;
} while  ( -e "$dir/$newfilename" );

$DEBUG && print "$dir/$newfilename seems unique\n";


# ============================================================================
# Third, do the transcode
#
$audiochannels = 6;
$audiostream = $audiostreamsurround;
if ( $audiostreamsurround eq "" )
{
  $audiochannels = 2;
  $audiostream = $audiostreamstereo;
} 

$command = "nice -n $nicevalue ffmpeg -i $file";
$command = "$command -acodec $audiocodec";
$command = "$command -ar $audiofrequency";
$command = "$command -ac $audiochannels";
$command = "$command -ab $audiobitrate";
$command = "$command -async 1";
$command = "$command -s $size";
$command = "$command -f $ftype";
$command = "$command -vcodec $videocodec";
$command = "$command -preset $videopreset";
$command = "$command -crf $videocrf";
$command = "$command -level 41";
$command = "$command $deinterlace";
$command = "$command -movflags $movflags";
$command = "$command $newfilename";

$DEBUG && print "Executing: $command\n";

chdir $dir;
system $command;

if ( ! -e "$dir/$newfilename" )
{   Die "Transcode failed\n"  }


# ============================================================================
# Last, copy the existing recorded details with the new file name.
#
Reconnect;
$query = $db->prepare("SELECT * FROM recorded $whereChanAndStarttime;");
$query->execute ||  Die "Unable to query recorded table";
$ref = $query->fetchrow_hashref;
$query->finish;

$ref->{'starttime'} = $newstarttime;
$ref->{'basename'}  = $newfilename;
if ( $DEBUG && ! $noexec )
{
    print 'Old file size = ' . (-s "$dir/$file")        . "\n";
    print 'New file size = ' . (-s "$dir/$newfilename") . "\n";
}
$ref->{'filesize'}  = -s "$dir/$newfilename";

my $extra = 'Copy';


#
# The new recording file has no cutlist, so we don't insert that field
#
my @recKeys = grep(!/^cutlist$/, keys %$ref);
my @recKeys = grep(!/^recordedid$/, keys %$ref);

#
# Build up the SQL insert command:
#
$command = 'INSERT INTO recorded (' . join(',', @recKeys) . ') VALUES ("';
foreach my $key ( @recKeys )
{
    if (defined $ref->{$key})
    {   $command .= quotemeta($ref->{$key}) . '","'   }
    else
    {   chop $command; $command .= 'NULL,"'   }
}

chop $command; chop $command;  # remove trailing comma quote

$command .= ');';

if ( $DEBUG || $noexec )
{   print "# $command\n"  }

if ( ! $noexec )
{   $db->do($command)  || Die "Couldn't create new recording's record, but transcoded file exists $newfilename\n"   }

# ============================================================================

$db->disconnect;
1;
