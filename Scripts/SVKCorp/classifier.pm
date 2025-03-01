package SVKCorp::classifier;
use warnings;
use strict;



my @note_classifier = (
  [qr/smiech/i, 'vocal', 'laughter'],
  [qr/zasmiatie/i, 'vocal', 'laughter'],
  [qr/potlesk/i, 'kinesic', 'applause'],
  [qr/Výkriky/i, 'vocal', 'shouting'],
  [qr/prestávka/i, 'incident', 'pause'],
  [qr/pauza/i, 'incident', 'pause'],
  [qr/prerušenie/i, 'incident', 'break'],
  [qr/gong/i, 'kinesic', 'ringing'],

);


sub note {
  my $text = shift;
  for my $c (@note_classifier){
    my ($re,$t,$cl) = @$c;
    return annotate_note($t, $cl) if $text =~ m/${re}/;
  }
  return {
    element => 'note'
  }
}

sub annotate_note {
  my $type = shift;
  my $subtype = shift;
  if ($type eq 'kinesic' || $type eq 'incident' || $type eq 'vocal' ) {
    return {
      element => $type,
      attribute => {
        name => 'type',
        value => $subtype
      },
      child => {
          element => 'desc'
      }
    }
  } else {
    return {
      element => $type,
      attribute => {
        name => 'type',
        value => $subtype
      }
    }    
  }
}


1;