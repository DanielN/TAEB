package TAEB::World::Monster;
use TAEB::OO;
use TAEB::Util qw/:colors align2str/;

use overload %TAEB::Meta::Overload::default;

has glyph => (
    isa      => 'Str',
    required => 1,
);

has color => (
    isa      => 'Str',
    required => 1,
);

has tile => (
    isa      => 'TAEB::World::Tile',
    weak_ref => 1,
    handles  => [qw/x y z level in_shop in_temple in_los distance/],
);

sub is_shk {
    my $self = shift;

    # if we've seen a nurse recently, then this monster is probably that nurse
    # we really need proper monster tracking! :)
    return 0 if TAEB->turn < (TAEB->last_seen_nurse || -100) + 3;

    return 0 unless $self->glyph eq '@' && $self->color eq COLOR_WHITE;

    # a shk isn't a shk if it's outside of its shop!
    # this also catches angry shks, but that's not too big of a deal
    return 0 unless $self->tile->type eq 'obscured'
                 || $self->tile->type eq 'floor';
    return $self->in_shop ? 1 : undef;
}

sub is_priest {
    my $self = shift;
    return 0 unless $self->glyph eq '@' && $self->color eq COLOR_WHITE;
    return ($self->in_temple ? 1 : undef);
}

sub is_oracle {
    my $self = shift;

    # we know the oracle level.. is it this one?
    if (my $oracle_level = TAEB->dungeon->special_level->{oracle}) {
        return 0 if $self->level != $oracle_level;
    }
    # if we don't know the oracle level, well, is this level in the right range?
    else {
        return 0 if $self->z < 5 || $self->z > 9;
    }

    return 0 unless $self->x == 39 && $self->y == 12;
    return 1 if TAEB->is_hallucinating
             || ($self->glyph eq '@' && $self->color eq COLOR_BRIGHT_BLUE);
    return 0;
}

sub is_vault_guard {
    my $self = shift;
    return 0 unless TAEB->following_vault_guard;
    return 1 if $self->glyph eq '@' && $self->color eq COLOR_BLUE;
    return 0;
}

sub is_quest_friendly {
    my $self = shift;

    # Attacking @s in quest level 1 will screw up your quest. So...don't.
    return 1 if $self->level->known_branch
             && $self->level->branch eq 'quest'
             && $self->z == 1
             && $self->glyph eq '@';
    return 0;
}

sub is_quest_nemesis {
    return 0; #XXX
}

sub is_enemy {
    my $self = shift;
    return 0 if $self->is_oracle;
    return 0 if $self->is_coaligned_unicorn;
    return 0 if $self->is_vault_guard;
    return 0 if $self->is_peaceful_watchman;
    return 0 if $self->is_quest_friendly;
    return 0 if $self->is_shk || $self->is_priest;
    return unless (defined $self->is_shk || defined $self->is_priest);
    return 1;
}

# Yes, this is different from is_enemy.  Enemies are monsters we should
# attack, hostiles are monsters we expect to attack us.  Even if they
# were perfect they'd be different, pick-wielding dwarves for instance.
#
# But they're not perfect, which makes the difference bigger.  If we
# decide to ignore the wrong monster, it will kill us, so is_enemy
# has to be liberal.  If we let a peaceful monster chase us, we'll
# starve, so is_hostile has to be conservative.

my %hate = ();

for (qw/HumGno OrcHum OrcElf OrcDwa/)
    { /(...)(...)/; $hate{$1}{$2} = $hate{$2}{$1} = 1; }

sub is_hostile {
    my $self = shift;

    # Otherwise, 1 if the monster is guaranteed hostile
    return 0 if !$self->spoiler;
    return 1 if $self->spoiler->{hostile};
    return 0 if $self->spoiler->{peaceful};
    return 0 if $self->is_quest_friendly;
    return 1 if $self->is_quest_nemesis;

    return 1 if $hate{TAEB->race}{$self->spoiler->{cannibal} || ''};

    return 1 if align2str $self->spoiler->{alignment} ne TAEB->align;

    # do you have the amulet? is it a minion?  is it cross-aligned?
    return;
}

sub probably_sleeping {
    my $self = shift;

    return 0 if TAEB->noisy_turn && TAEB->noisy_turn + 40 > TAEB->turn;
    return $self->glyph =~ /[ln]/ || TAEB->senses->is_stealthy;
}

# Would this monster chase us if it wanted to and noticed us?
sub would_chase {
    my $self = shift;

    # Unicorns won't step next to us anyway
    return 0 if $self->is_unicorn;

    # Leprechauns avoid the player once they have gold
    return 0 if $self->glyph eq 'l';

    # Monsters that can't move won't take initiative
    return 0 if !$self->can_move;

    return 1;
}

sub will_chase {
    my $self = shift;

    return $self->would_chase
        && $self->is_hostile
        && !$self->probably_sleeping;
}

sub is_meleeable {
    my $self = shift;

    return 0 unless $self->is_enemy;

    # floating eye (paralysis)
    return 0 if $self->color eq COLOR_BLUE
             && $self->glyph eq 'e'
             && !TAEB->is_blind;

    # blue jelly (cold)
    return 0 if $self->color eq COLOR_BLUE
             && $self->glyph eq 'j'
             && !TAEB->cold_resistant;

    # spotted jelly (acid)
    return 0 if $self->color eq COLOR_GREEN
             && $self->glyph eq 'j';

    # gelatinous cube (paralysis)
    return 0 if $self->color eq COLOR_CYAN
             && $self->glyph eq 'b'
             && $self->level->has_enemies > 1;

    return 1;
}

# Yes, I know the name is long, but I couldn't think of anything better.
#  -Sebbe.
sub is_seen_through_warning {
    my $self = shift;
    return $self->glyph =~ /[1-5]/;
}

sub is_sleepable {
    my $self = shift;
    return $self->is_meleeable;
}

sub respects_elbereth {
    my $self = shift;

    return 0 if $self->glyph =~ /[A@]/;
    return 0 if $self->is_minotaur;
    # return 0 if $self->is_rider;
    # return 0 if $self->is_blind && !$self->is_permanently_blind;

    return 1;
}

sub is_minotaur {
    my $self = shift;
    $self->glyph eq 'H' && $self->color eq COLOR_BROWN
}

sub is_unicorn {
    my $self = shift;
    return 0 if $self->glyph ne 'u';
    return 0 if $self->color eq COLOR_BROWN;

    # this is coded somewhat strangely to deal with black unicorns being
    # blue or dark gray
    if ($self->color eq COLOR_WHITE) {
        return 'Law';
    }

    if ($self->color eq COLOR_GRAY) {
        return 'Neu';
    }

    return 'Cha';
}

sub is_coaligned_unicorn {
    my $self = shift;
    my $uni = $self->is_unicorn;

    return $uni && $uni eq TAEB->align;
}

sub is_peaceful_watchman {
    my $self = shift;
    return 0 unless $self->level->is_minetown;
    return 0 if $self->level->angry_watch;
    return 0 unless $self->glyph eq '@';

    return $self->color eq COLOR_GRAY || $self->color eq COLOR_GREEN;
}

sub is_ghost {
    my $self = shift;

    return $self->glyph eq ' ' if $self->level->is_rogue;
    return $self->glyph eq 'X';
}

sub can_move {
    my $self = shift;

    # spotted jelly, blue jelly
    return 0 if $self->glyph eq 'j';

    # brown yellow green red mold
    return 0 if $self->glyph eq 'F';

    return 0 if $self->is_oracle;
    return 1;
}

sub debug_line {
    my $self = shift;
    my @bits;

    push @bits, sprintf '(%d,%d)', $self->x, $self->y;
    push @bits, 'g<' . $self->glyph . '>';
    push @bits, 'c<' . $self->color . '>';

    return join ' ', @bits;
}

=head2 spoiler :: hash

Returns the monster spoiler (L<TAEB::Spoiler::Monster>) entry for this thing,
or undef if the symbol does not uniquely determine the monster.

=cut

sub spoiler {
    my $self = shift;

    my @candidates = TAEB::Spoilers::Monster->search(
        glyph => $self->glyph,
        color => $self->color,
    );

    return if @candidates > 2;
    return $candidates[1];
}

=head2 can_be_outrun :: bool

Return true if the player can definitely outrun the monster.

=cut

sub can_be_outrun {
    my $self = shift;

    my $spoiler = $self->spoiler || return 0;
    my $spd = $spoiler->{speed};
    my ($pmin, $pmax) = TAEB->speed;

    return $spd < $pmin || ($spd == $pmin && $spd < $pmax);
}

=head2 should_attack_at_range :: Bool

Returns true if the monster is (probably) dangerous in melee to the point
where wand charges and kiting are preferable.

=cut

sub should_attack_at_range {
    my $self = shift;

    return 1 if $self->glyph eq 'n';
    return 1 if $self->is_minotaur;

    # add other things as they become a problem / replace with better spoiler
    # handling...

    return 0;
}

=head2 can_be_infraseen :: Bool

Returns true if the player could see this monster using infravision.

=cut

sub can_be_infraseen {
    my $self = shift;

    return TAEB->has_infravision
        && $self->glyph !~ /[abceijmpstvwyDEFLMNPSWXZ';:~]/; # evil evil should be in T:M:S XXX
}

=head2 danger_level -> Int

Returns a number indicating a rating of how difficult the monster is.

Since it should only be used to sort monsters into difficulty, don't worry
about this function's range.

=cut

sub danger_level {
    my $self = shift;

    return 1 if !$self->respects_elbereth;
    return 0;
}

__PACKAGE__->meta->make_immutable;
no TAEB::OO;

1;

