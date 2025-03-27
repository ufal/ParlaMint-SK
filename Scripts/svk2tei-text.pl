#!/usr/bin/env perl

use warnings;
use strict;
use open qw(:std :utf8);
use utf8;
binmode STDERR, 'utf8';
binmode STDIN,  'utf8';
binmode STDOUT, 'utf8';
use Getopt::Long;
use XML::LibXML;
use XML::LibXML::PrettyPrint;
use DateTime::Format::Strptime;

use File::Basename;
use File::Path;
use File::Spec;
use Data::Dumper;

use SVKCorp::reader;
use SVKCorp::classifier;

my $tz = 'Europe/Prague';
my $strp = DateTime::Format::Strptime->new(
  pattern   => '%e. %B %Y',
  locale    => 'sk_SK',
  time_zone => $tz
);

my $out_dir;
my @in_files;

GetOptions (
    'out-dir=s' => \$out_dir,
    'in-files=s{1,}' => \@in_files,
  );

unless($out_dir){
  print STDERR "no output directory\n";
  exit 1;
}

my $parser = XML::LibXML->new();

$out_dir = File::Spec->rel2abs($out_dir);
my $data = SVKCorp::reader->new(files=>[map {File::Spec->rel2abs($_)} @in_files], parse_speech =>1, split_speech =>1);

my $day;

while(my $speech = $data->next_row()){
  if($speech->{first_speech}){
    save_day($day, $out_dir) if $day;
    $day = init_day($speech);
  }
  my @move_to_next_day = (add_speech($day, $speech));
  if(@move_to_next_day){
    save_day($day, $out_dir) if $day;
    # update date from $move_to_next_day[0]
    ## Desiaty deň rokovania 49. schôdze Národnej rady Slovenskej republiky 15. júla 1998
    my ($date) = $move_to_next_day[0]->{content} =~ m/(\d+\.\s+\w+\s+\d\d\d\d)/;
    print STDERR "INFO: new day recognized $date (";
    $date = $strp->parse_datetime("$date");
    my $new_date = $date->strftime('%Y%m%d');
    print STDERR "$new_date)\n";
    # patch date in $data
    $data->set_date_patcher($speech->{raw}->{date}, $new_date);
    # init day with correct day
    $data->self_update($speech->{raw});
    $data->{speeches} -= 1;
    $speech->{parlamint}->{tei_id} = $data->{tei_id};
    $speech->{parlamint}->{date} = $data->{date_formated};
    $day = init_day($speech);
    # insert notes
    $speech->{parlamint}->{content} = [@move_to_next_day];
    @move_to_next_day = (add_speech($day, $speech));
    #while(@move_to_next_day) {
    #  my $note = note_element(shift @move_to_next_day);
    #  $day->{div}->appendChild($note) if $note;
    #}
  }
}

$data->delete();
save_day($day, $out_dir) if $day;


sub add_speech {
  my ($day, $speech) = @_;
  log_source($day->{div},$speech);
  my $utterance = $day->{div}->addNewChild(undef,'u');
  $utterance->setAttributeNS('http://www.w3.org/XML/1998/namespace','id',$speech->{parlamint}->{u_id});
  my $who = $speech->{parlamint}->{speaker_id} ? '#'.$speech->{parlamint}->{speaker_id} : $speech->{raw}->{fullname};
  $utterance->setAttribute('who',$who) if $who;
  $utterance->setAttribute('ana',($speech->{raw}->{moderator} ? '#chair' : '#regular'));
  $utterance->setAttribute('source',$speech->{parlamint}->{u_url}) if $speech->{parlamint}->{u_url};
  my $seg = $utterance->addNewChild(undef,'seg');
  $seg->setAttributeNS('http://www.w3.org/XML/1998/namespace','id',$speech->{parlamint}->{u_id}.'.p1');


  ## print STDERR "TODO: move this to reader!!!\n";
  my @content_next_day = @{$speech->{parlamint}->{content}//[]};
  my @content = (shift @content_next_day); # insert first data
  while(@content_next_day){
    if( not($content_next_day[0]->{is_text}) 
        && $content_next_day[0]->{content} =~ m/deň rokovania.*schôdze Národnej rady Slovenskej/) {
      last;
    }
    push @content, (shift @content_next_day);
  }
  # print notes and skip whitespaces before utterance
  while(@content && (not($content[0]->{is_text}) || $content[0]->{content} =~ /^\s+$/)) {
    my $note = note_element(shift @content);
    $day->{div}->insertBefore($note,$utterance) if $note;
  }
  # get notes and skip whitespaces after utterance
  my @context_after = ();
  while(@content && (not($content[-1]->{is_text}) || $content[-1]->{content} =~ /^\s+$/)) {
    my $content = pop @content;
    next if $content->{is_text};
    unshift @context_after, $content;
  }
  # print utterance content into one paragraph
  while(@content) {
    my $content = shift @content;
    if($content->{is_text}){
      $seg->appendText($content->{content});
    } else {
      my $note = note_element($content);
      $seg->appendChild($note) if $note;
    }
  }  
  while(@context_after){
    my $content = shift @context_after;
    my $note = note_element($content);
    $day->{div}->appendChild($note) if $note;
  }
  
  return @content_next_day;
}


sub log_source {
  my ($element, $speech) = @_;
  $element->appendChild(XML::LibXML::Comment->new( "orig: ".$speech->{raw}->{svk_source}." || sorted: ". $speech->{source} ));
}


# create a note-like element
sub note_element {
  my $content = shift;
  return if $content->{is_text};
  my $note_type = SVKCorp::classifier::note($content->{content});
  my $note = XML::LibXML::Element->new($note_type->{element});
  $note->setAttribute($note_type->{attribute}->{name}, $note_type->{attribute}->{value}) if $note_type->{attribute};
  my $ptr_element = $note;
  while($note_type->{child}){
    $note_type = $note_type->{child};
    $ptr_element = $ptr_element->addNewChild(undef,$note_type->{element});
    $ptr_element->setAttribute($note_type->{attribute}->{name}, $note_type->{attribute}->{value}) if $note_type->{attribute};
  }
  $ptr_element->appendText($content->{content} );
  return $note;
}

sub save_day {
  my ($day, $dir) = @_;
  save_xml($day->{tei}, File::Spec->catfile($dir,substr($day->{date},0,4),$day->{id}.'.xml'));
}


sub init_day {
  my ($speech) = @_;
  my $tei = XML::LibXML::Document->new("1.0", "utf-8");
  my $root_node = XML::LibXML::Element->new('TEI');
  $tei->setDocumentElement($root_node);
  my $id = $speech->{parlamint}->{tei_id};
  my $date = $speech->{parlamint}->{date};
  my $url = $speech->{parlamint}->{doc_url} // '';
  my $term = $speech->{raw}->{term};
  my $meeting = $speech->{raw}->{meeting};


  $root_node->setNamespace('http://www.tei-c.org/ns/1.0','',1);
  $root_node->setAttributeNS('http://www.w3.org/XML/1998/namespace','id',$id);
  $root_node->setAttributeNS('http://www.w3.org/XML/1998/namespace','lang','sk');
 
  $url = '<idno type="URI" subtype="parliament">'.$url.'</idno>' if $url;
  my $teiHeader = $parser->parse_balanced_chunk(
<<HEADER
<teiHeader>
  <fileDesc>
         <titleStmt>
            <!-- TODO -->
            <meeting ana="#parla.term #parla.uni" n="$term">$term</meeting>
            <meeting ana="#parla.meeting #parla.uni" n="$meeting">$meeting</meeting>
            <!-- TODO -->
         </titleStmt>
         <editionStmt>
            <edition>3.0a</edition>
         </editionStmt>
         <extent>
           <!-- TODO -->
         </extent>
         <publicationStmt>
            <!-- TODO -->
         </publicationStmt>
         <sourceDesc>
            <bibl>
               <!-- TODO -->
               $url
               <date when="$date">$date</date>
            </bibl>
         </sourceDesc>
      </fileDesc>
      <encodingDesc>
         <!-- TODO -->
      </encodingDesc>
      <profileDesc>
         <settingDesc>
            <setting>
               <!-- TODO -->
               <date when="$date">$date</date>
            </setting>
         </settingDesc>
         <!-- TODO -->
      </profileDesc>
   </teiHeader>
HEADER
    );
  $root_node->appendChild($teiHeader);
  my $div = $root_node->addNewChild(undef,'text')->addNewChild(undef,'body')->addNewChild(undef,'div');
  print STDERR "INFO: Processing $date ($id)\n";
  return {
    id => $id,
    date => $date,
    tei => $tei,
    div => $div
  };
}



####################

sub to_string {
  my $doc = shift;
  my $pp = XML::LibXML::PrettyPrint->new(
    indent_string => "   ",
    element => {
        inline   => [qw//], # note
        block    => [qw/person/],
        compact  => [qw/catDesc term label date edition title meeting idno orgName persName resp licence language sex forename surname measure head roleName/],
        preserves_whitespace => [qw/s seg note ref p desc name/],
        }
    );
  $pp->pretty_print($doc);
  return $doc->toString();
}

sub print_xml {
  my $doc = shift;
  binmode STDOUT;
  print to_string($doc);
}

sub save_xml {
  my ($doc,$filename) = @_;
  print STDERR "INFO: Saving to $filename\n";
  my $dir = dirname($filename);
  File::Path::mkpath($dir) unless -d $dir;
  open FILE, ">$filename";
  binmode FILE;
  my $raw = to_string($doc);
  print FILE $raw;
  close FILE;
}