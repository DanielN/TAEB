#!/usr/bin/env perl

package TAEB::AI::Behavior::Chokepoint;
use TAEB::OO;
use TAEB::Util 'vi2delta', 'angle';
extends 'TAEB::AI::Behavior';

#    .|  We look at a direction as being suitible for running to if it
#   ...  lacks interesting monsters in the inner quadrant, but has a
# @...|  usable chokepoint.  No pathfinding is needed, because we will
#   ..|  just run this again next round, and we do not intend to use
#    .|  chokepoints outside LOS for informational reasons.

#   ..    .   .
# @..|  @.|  @
#   .|    |

# Of course, it has to be a _good_ chokepoint.  We answer that by saying
# it has less walkable neighbors than we do now.

# A quadrant is specified as the intersection of half-planes defined by linear
# functions.

sub vulnerability {
    my ($self, $dir, $tile) = @_;

    # Always try to fight on stairs
    return -1 if $tile->type eq 'stairsup' || $tile->type eq 'stairsdown';

    my $score = 0;

    # Or on an E-able square, if the monsters aren't E-ignorers
    if (!grep { $_->ignores_elbereth && $_->in_los }
            TAEB->current_level->has_enemies) {
        $score += 5 if !$tile->is_inscribable;
    }

    $score += $tile->grep_adjacent(sub {
        my ($tile2, $dir2) = @_;

        # Ignore back directions to reduce the likelyhood of self-cornering.
        $tile2->is_walkable || angle($dir2, $dir) <= 1;
    });

    $score;
}

sub useful_dir {
    my ($self, $dir) = @_;
    my ($dx, $dy) = delta2vi $dir;
    my $choke = 0;

    my $cut = $self->vulnerability($dir, TAEB->current_tile);

    for $dy (-7 .. 7) {
        for $dx (-7 .. 7) {
            my $tile = TAEB->current_level->at(TAEB->x + $dx, TAEB->y + $dy);

            next unless $tile;
            next unless $tile->in_los;
            next unless $tile->x * ( $dx - $dy) + $tile->y * ( $dx + $dy) > 0;
            next unless $tile->x * ( $dx + $dy) + $tile->y * (-$dx + $dy) > 0;

            if ($self->vulnerability($dir, $tile) < $cut) {
                $choke = 1;
            }

            if ($tile->has_enemy) {
                return 0;
            }
        }
    }

    return 0 unless $choke;

    my $to = TAEB->current_level->at_direction($dir);

    return 0 unless defined $to
               && $to->is_walkable
               && !$to->has_monster
               && $to->type ne 'trap';

    return 0 if (TAEB->current_tile->type eq 'opendoor'
            || $to->type eq 'opendoor')
           && $dir =~ /[yubn]/;

    return 1;
}

sub prepare {
    my $self = shift;

    my @enemies = grep { $_->in_los } TAEB->current_level->has_enemies;

    # Useless in one-on-one fights
    return if @enemies <= 1;

    my @dirs = grep { $self->useful_dir($_) } qw/h j k l y u b n/;

    if (@dirs) {
        $self->do(move => direction => $dirs[0]);
        $self->currently("Running for a chokepoint");
        $self->urgency('normal');
    }
}

sub urgencies {
    return {
        normal => "running for a chokepoint",
    };
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

