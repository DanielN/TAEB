package TAEB::Action::Search;
use TAEB::OO;
extends 'TAEB::Action';

has started => (
    isa     => 'Int',
    default => sub { TAEB->turn },
);

has iterations => (
    traits   => [qw/TAEB::Provided/],
    isa      => 'Int',
    default  => 20,
);

sub command { shift->iterations . 's' }

sub done {
    my $self = shift;
    my $diff = TAEB->turn - $self->started;

    TAEB->each_adjacent_inclusive(sub {
        my $self = shift;
        $self->inc_searched($diff);
    });
}

__PACKAGE__->meta->make_immutable;
no TAEB::OO;

1;

