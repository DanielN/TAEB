#!/usr/bin/env perl
package TAEB::Config;
use TAEB::OO;
use YAML;
use Hash::Merge 'merge';
Hash::Merge::set_behavior('RIGHT_PRECEDENT');

has file => (
    is      => 'ro',
    isa     => 'Str',
    default => 'etc/config.yml',
);

has contents => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { {} },
);

sub BUILD {
    my $self = shift;

    my @config = $self->file;

    my %seen;

    while (my $file = shift @config) {
        next if $seen{$file}++;
        next if !-f $file;

        my $config = YAML::LoadFile($file);
        $self->contents(merge($self->contents, $config));

        # if this config specified other files, load them too
        if ($config->{other_config}) {
            my $c = $config->{other_config};
            if (ref($c) eq 'ARRAY') {
                push @config, @$c;
            }
            elsif (ref($c) eq 'HASH') {
                push @config, keys %$c;
            }
            else {
                push @config, $c;
            }
        }
    }
}

=head2 get_role

Retrieves the role from the config, or picks randomly.

=cut

sub get_role {
    my $self = shift;
    my $role = $self->contents->{role}
        or return '*';
    return $1
        if lc($role) =~ /^([abchkmpstvw])/;
    return 'r'
        if $role =~ /^R[^a]/ || $role eq 'r';
    return 'R'
        if $role =~ /^Ra/i || $role eq 'R';
    return '*';
}

=head2 get_race

Retrieves the race from the config, or picks randomly.

=cut

sub get_race {
    my $self = shift;
    my $role = $self->contents->{race}
        or return '*';
    return $1
        if lc($role) =~ /^([hedgo])/;
    return '*';
}

=head2 get_gender

Retrieves the gender from the config, or picks randomly.

=cut

sub get_gender {
    my $self = shift;
    my $role = $self->contents->{gender}
        or return '*';
    return $1
        if lc($role) =~ /^([mf])/;
    return '*';
}

=head2 get_align

Retrieves the alignment from the config, or picks randomly.

=cut

sub get_align {
    my $self = shift;
    my $role = $self->contents->{align} || $self->contents->{alignment}
        or return '*';
    return $1
        if lc($role) =~ /^([lnc])/;
    return '*';
}

# yes autoload is bad. but, I am lazy
our $AUTOLOAD;
sub AUTOLOAD {
    my $self = shift;
    $AUTOLOAD =~ s{.*::}{};

    if (@_) {
        TAEB->config->contents->{$AUTOLOAD} = shift;
    }

    return TAEB->config->contents->{$AUTOLOAD};
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

