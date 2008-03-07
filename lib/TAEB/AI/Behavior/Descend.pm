#!/usr/bin/env perl
package TAEB::AI::Behavior::Descend;
use Moose;
extends 'TAEB::AI::Behavior::GotoTile';

sub match_tile {
    shift->floor_glyph eq '>' ? ('>', 'Descending') : undef
}

use constant tile_description => 'the downstairs';
use constant using_urgency    => 'descending';

make_immutable;

1;

