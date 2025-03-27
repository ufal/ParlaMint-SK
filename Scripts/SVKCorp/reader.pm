package SVKCorp::reader;
use warnings;
use strict;
use Text::CSV qw/csv/;
use Data::Dumper;
use HTML::Entities;
use open qw(:std :utf8);
use utf8;

sub new {
  my($classname, @arguments) = @_;
  my %args = @arguments;
  my $obj = { 
    files => $args{files},
    file_idx => undef,
    tsv_record => undef,
    fh => undef,
    date => undef,
    date_formated => undef,
    tei_id => undef,
    tei_id_seen => {},
    tei_id_seen_n => {},
    current_row => undef,
    parse_speech => !!$args{parse_speech},
    split_speech => !!$args{split_speech},
    patch_date => {},
    tsv => Text::CSV->new(
      {
        binary => 1,
        auto_diag => 1,
        sep_char=> "\t",
        quote_char => undef,
        escape_char => '"',
        empty_is_undef => 1,
        blank_is_undef => 1,
        callbacks => {
          after_parse => sub {
            my ($csv, $row) = @_;
            for my $i (0..@$row) {
              $row->[$i] = undef if $row->[$i] && $row->[$i] eq 'NA';
              $row->[$i] = undef if $row->[$i] && $row->[$i] eq 'NA, NA.';
              if($row->[$i]){
                $row->[$i] = decode_entities($row->[$i]);
                $row->[$i] =~ s|<br[ \/]*?>| |g;
                $row->[$i] =~ s|<.+?>||g;
                $row->[$i] =~ s|  *| |g;
              }
            }
          }
        }
      })
  };
  bless $obj, $classname;
  return $obj;
}

sub delete {
   my $self = shift;
   close $self->{fh} if $self->{fh};
   undef(%$self);
}


sub next_row {
  my $self = shift;

  my $row;
  my @content;
  if ($self->{current_row}) {
    $row = $self->{current_row};
  } else {
    $self->open_next_file() unless $self->{fh};
    $row = $self->{tsv}->getline_hr($self->{fh});
    unless ($row) {
      return unless $self->open_next_file();
      $row = $self->{tsv}->getline_hr ($self->{fh});
    }
    return unless $row;
    patch_text($row);
    $self->{tsv_record} += 1;
  }

  if ($self->{split_speech}) {
    # get speech from the begining, until first "Tóth, Vojtech, poslanec NR SR" like string is present
    my ($speech, $next_speaker, $next_speech) = split_speech($row->{speech});
    $self->error("speech is starting with next speaker => empty speech") unless $speech; # this produces an empty speech !!!
    $row->{speech} = $speech;
    # save the rest of speech to $self->{current_row} and update speaker values in current_row
    if($next_speaker){
      $self->warn("splitting speech '".$row->{fullname}."' and '$next_speaker'");
      $self->{current_row} = {%$row};
      $self->{current_row}->{$_} = undef for qw/type mp_id moderator fullname firstname lastname title party party_short dob gender nationality residence district email personal_web mp_web difterm speech lem/;
      $self->{current_row}->{moderator} = ($next_speaker =~ m/ (?:pod)?predsed/);
      $self->{current_row}->{fullname} = $next_speaker;
      $self->{current_row}->{speech} = $next_speech;

    } else {
      $self->{current_row} = undef;
    }
  }  

  $self->self_update($row);
  my $src = $self->{files}->[$self->{file_idx}].":line=".($self->{tsv_record}+1);
  $src =~ s#^.*/##;
  my $tei_id = $self->{tei_id};
  $tei_id .= "s".$self->{tei_id_seen_n}->{$tei_id} if $self->{tei_id_seen_n}->{$tei_id};
  return {
    raw => $row,
    first_speech => ($self->{speeches} == 1),
    source => $src,
    parlamint => {
      tei_id => $tei_id,
      u_id => $tei_id.".u".$self->{speeches},
      speaker_id => get_speaker_id($row),
      date => $self->{date_formated} ,
      content => [split_content($row->{speech})],
      doc_url => $row->{transcript_link} =~ /documentId/ ? $row->{transcript_link} : undef,
      u_url => $row->{transcript_link} =~ /transcript/ ? $row->{transcript_link} : undef,
      }
    };
}

sub self_update {
  my $self = shift;
  my $row = shift;
  my $date = $self->patch_date($row->{date});
  my $date_formated = join('-', unpack "A4A2A2", $date);
  my $tei_id = "ParlaMint-SK_$date_formated-t".$row->{term}."m".($row->{meeting}//'--');
  
  my $date_change = ($date != $self->{date});
  if($date_change){
    $self->info("date change ".$self->{date}." => ".$date);
    $self->error("date change (wrong date order)".$self->{date}." => ".$date) if $date < $self->{date};
  }
  my $first_speech = not(defined $self->{tei_id}) || $self->{tei_id} ne $tei_id;
  $self->{speeches} = 0 if $first_speech;
  $self->{speeches} += 1;
  if(defined $self->{tei_id_seen}->{$tei_id} && $first_speech){
    $self->error("Duplicit document ID $tei_id (previous on row ".$self->{tei_id_seen}->{$tei_id}.")");
    $self->{tei_id_seen_n}->{$tei_id} //= 0;
    $self->{tei_id_seen_n}->{$tei_id} += 1;
  }
  $self->{date} = $date;
  $self->{date_formated} = $date_formated;
  $self->{tei_id} = $tei_id;
  $self->{tei_id_seen}->{$tei_id} = $self->{tsv_record};
  return $self;
}

sub set_date_patcher {
  my $self = shift;
  my $in = shift;
  my $out = shift;
  $self->{patch_date} = { $in => $out};
  print STDERR "INFO: setting date patcher $in => $out\n";
  return $self;  
}
sub patch_date {
  my $self = shift;
  my $in = shift;
  if ($self->{patch_date}->{$in}) {
    return $self->{patch_date}->{$in}
  }
  $self->{patch_date} = {};
  return $in;
}

sub patch_text {
  my $row = shift;
  $row->{speech} =~ s/([\p{Lu}\p{Lt}][\p{Lu}\p{Lt}\p{Ll}]* deň rokovania.*?schôdze Národnej rady Slovenskej republiky.*?\d\d\d\d(?: o .*? hodine)?)(?: 1\.)?/($1)/;
  $row->{speech} =~ s/__+//g;
}

sub get_speaker_id {
  my $row = shift;
  my $dob = '';
  if($row->{dob}) {
    $dob =substr(".".$row->{dob},0,5);
  }
  my $result = ($row->{firstname}||'').($row->{lastname}||'').$dob;
  $result =~ s/ //g;
  return $result
}

sub split_speech {
  my $text = shift;
  return (undef, undef, undef) unless $text;
  my $re_speaker = qr/(?:(?:\b[\p{Lu}\p{Lt}][\p{Lu}\p{Lt}\p{Ll}]*,?\s){2}(?:doteraj[\p{Ll}]*\s)?p[\p{Ll}]* NR SR)/;
  if($text =~ m/^\s*(.*?)\s*(?:\s*\d+\.)?(${re_speaker})(?:\s*\d+\.)?\s*(.*?)\s*$/) {
    return ($1,$2,$3);
  }
  return ($text,undef,undef);
}

# split text content into leading/trailing spaces, notes, speech content
sub split_content {
  my $text = shift;
  my $orig = $text;
=textsamples
  ktorý znie: „Zákon č. 333/2011 Z. z. o orgánoch
  Slovenskej republiky. (2) Monitorovací výbor
  dopĺňať zákon č. 25/ 2006 z. z.
=cut
  my $re_slash = qr/(?<!\d\s?)\/(?!\s?\d)/;
  my $re_law = qr/(?:\(§ \d+(?: ods. 5(?: bod 3)?)?\))/;
  my $re_note = qr/(?:\[[\S].*?[\S]\]|\((?!\S\.?\)).*?(?:(?<!\([0-9]{,5}\.| [a-z0-9])|ods. \d+|písm. [a-z]|bod [a-z0-9])\)|${re_slash}[\S].*?[\S]${re_slash})/;
  my $re_text = qr/(?:.+?)/;
  my @content;
  while($text){
    if ($text =~ s/^(\s+)//) {
      push @content, {is_text => 1, content => $1};
    } elsif ($text =~ s/^(${re_law})//) {
      push @content, process_note($1);
    }  elsif ($text =~ s/^(${re_note})//) {
      push @content, process_note($1);
    } elsif ($text =~ s/^(${re_text})(\s*)(${re_law})//) {
      push @content, process_text($1);
      push @content, process_text($2);
      push @content, process_note($3);
    } elsif ($text =~ s/^(${re_text})(\s*)(${re_note})//) {
      push @content, process_text($1);
      push @content, process_text($2);
      push @content, process_note($3);
    } else {
      push @content, process_text($text);
      $text = '';
    }
  }
  return @content
}

sub process_note {
  my $s = shift;
  $s = substr $s, 1, -1;
  $s =~ s/^ *| *$//g;
  return {is_text => 0, content => $s};
}

sub process_text {
  my $s = shift;
  $s =~ s/===*/ /g;
  $s =~ s/\*\*\**/ /g;
  $s =~ s/  */ /g;
  return {is_text => 1, content => $s};
}

sub open_next_file {
  my $self = shift;
  close $self->{fh} if $self->{fh};
  $self->{tsv_record} = undef;
  $self->{file_idx} //= -1;
  $self->{file_idx} += 1;
  return 0 if $self->{file_idx} >= @{$self->{files}};
  my $file = $self->{files}->[$self->{file_idx}];
  open $self->{fh}, "<:encoding(utf8)", $file  or die "$file: $!";
  my @cols = @{$self->{tsv}->getline($self->{fh})};
  $self->{tsv}->column_names(@cols);
  $self->{tsv_record} = 0;
  return 1;
}

sub log {
  my $self = shift;
  my $text = shift;
  my $status = shift // 'INFO';
  print STDERR "$status: ".$self->{files}->[$self->{file_idx}].":".($self->{tsv_record}+1)." $text\n";
}
sub info {
  my $self = shift;
  my $text = shift;
  $self->log($text, 'INFO');
}
sub warn {
  my $self = shift;
  my $text = shift;
  $self->log($text, 'WARN');
}
sub error {
  my $self = shift;
  my $text = shift;
  $self->log($text, 'ERROR');
}


1;