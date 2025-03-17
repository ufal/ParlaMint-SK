package SVKCorp::classifier;
use warnings;
use strict;
use open qw(:std :utf8);
use utf8;



my @note_classifier = (
  [qr/deň rokovania.*hodine/i, 'note', 'time'],
  [qr/deň rokovania/i, 'note', 'date'],
  [qr/hlasovanie/i, 'note', 'narrative'],
  [qr/striedanie predsedajúcich/i, 'note', 'narrative'],
  [qr/smiech/i, 'vocal', 'laughter'],
  [qr/zasmiatie/i, 'vocal', 'laughter'],
  [qr/potlesk/i, 'kinesic', 'applause'],
  [qr/krik/i, 'vocal', 'shouting'],
  [qr/prestávka/i, 'incident', 'pause'],
  [qr/pauza/i, 'incident', 'pause'],
  [qr/prerušenie/i, 'incident', 'break'],
  [qr/gong/i, 'kinesic', 'ringing'],
  [qr/časom[i]?er/i, 'kinesic', 'ringing'],
  [qr/hlas.?/i, 'vocal', 'noise'],
  [qr/šum/i, 'kinesic', 'noise'],
  [qr/ruch/i, 'vocal', 'noise'],
  [qr/hluk/i, 'vocal', 'noise'],
  [qr/reakci[ea]/i, 'vocal', 'speaking'],
  [qr/odpoved/i, 'vocal', 'speaking'],
  [qr/rokovanie o/i, 'note', 'narrative'],
  [qr/tlač (?:č\S* )?\d+/i, 'note', 'comment'],
  [qr/nezrozumiteľ/i, 'gap', 'inaudible'],
  [qr/\b(?:nebolo|nie)\b.*(?:počuť|rozumieť)/i, 'gap', 'inaudible'],
  [qr/nepočuť/i, 'gap', 'inaudible'], 
  [qr/(?:reakcia|odpoveď|poznámk|námietka) .*z pléna/i, 'vocal', 'speaking'],
  [qr/po prestávke/i, 'note', 'comment'],
  [qr/pozn\. red\./i, 'note', 'comment'],
  [qr/pokracovanie/i, 'note', 'comment'],
  [qr/(?:hovoren|povedan|vysloven)\S* súbežne/i, 'note', 'comment'],
  [qr/pobaven/i, 'vocal', 'laughter'],
  [qr/úsmevo/i, 'vocal', 'laughter'],
  [qr/zákon/i, 'note', 'comment'],
  [qr/minúta ticha/i, 'incident', 'pause'], ### not sure about correct clasification
  [qr/hymna/i, 'kinesic', 'playback'],
  [qr/prítomných/i, 'note', 'quorum'],
  [qr/prezentácia/i, 'note', 'quorum'],
);


sub note {
  my $text = shift;
  for my $c (@note_classifier){
    my ($re,$t,$cl) = @$c;
    return annotate_note($t, $cl) if $text =~ /$re/;
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
  } elsif ($type eq 'gap' ) {
    return {
      element => $type,
      attribute => {
        name => 'reason',
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