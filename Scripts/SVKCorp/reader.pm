package SVKCorp::reader;
use warnings;
use strict;
use Text::CSV qw/csv/;
use Data::Dumper;
use HTML::Entities;

sub new {
  my($classname, @arguments) = @_;
  my %args = @arguments;
  my $obj = { 
    files => $args{files},
    file_idx => undef,
    tsv_record => undef,
    fh => undef,
    date => undef,
    tei_id => undef,
    tei_id_seen => {},
    current_row => undef,
    parse_speech => !!$args{parse_speech},
    split_speech => !!$args{split_speech},
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

  my $date = join('-', unpack "A4A2A2", $row->{date});
  my $tei_id = "ParlaMint-SK_$date-t".$row->{term}."m".($row->{meeting}//'--');
  
  my $first_speech = not(defined $self->{tei_id}) || $self->{tei_id} ne $tei_id;
  $self->{speeches} = 0 if $first_speech;
  $self->{speeches} += 1;
  if(defined $self->{tei_id_seen}->{$tei_id} && $first_speech){
    $self->error("Duplicit document ID $tei_id");
  }
  $self->{date} = $row->{date};
  $self->{tei_id} = $tei_id;
  $self->{tei_id_seen}->{$tei_id} = 1;
  return {
    raw => $row,
    first_speech => $first_speech,
    parlamint => {
      tei_id => $tei_id,
      u_id => "$tei_id.u".$self->{speeches},
      speaker_id => get_speaker_id($row),
      date => $date,
      content => [split_content($row->{speech})],
      doc_url => $row->{transcript_link} =~ /documentId/ ? $row->{transcript_link} : undef,
      u_url => $row->{transcript_link} =~ /transcript/ ? $row->{transcript_link} : undef,
      }
    };
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
  if($text =~ m/^\s*(.*?)\s*(${re_speaker})(?:\s*\d+\.)\s*(.*?)\s*$/) {
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
    } elsif ($text =~ s/^(${re_text})(\s*)(${re_law})//) {
      push @content, {is_text => 1, content => $1};
      push @content, {is_text => 1, content => $2};
      push @content, process_note($3);
    } elsif ($text =~ s/^(${re_text})(\s*)(${re_note})//) {
      push @content, {is_text => 1, content => $1};
      push @content, {is_text => 1, content => $2};
      push @content, process_note($3);
    } elsif ($text =~ s/^(${re_law})//) {
      push @content, process_note($1);
    }  elsif ($text =~ s/^(${re_note})//) {
      push @content, process_note($1);
    } else {
      push @content, {is_text => 1, content => $text};
      $text = '';
    }
  }
  return @content
}

sub process_note {
  my $s = shift;
  $s = substr $s, 1, -1;
  return {is_text => 0, content => $s};
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