use strict;
use warnings;
package TAEB::Logger;
use TAEB::OO;
use Log::Dispatch::Twitter;
use Log::Dispatch::File;
use Carp;
extends 'Log::Dispatch::Channels';

has default_outputs => (
    isa     => 'ArrayRef[Log::Dispatch::Output]',
    lazy    => 1,
    default => sub { [] },
);

has bt_levels => (
    isa     => 'HashRef',
    lazy    => 1,
    default => sub { { error => 1, warning => 1 } },
);

has everything => (
    isa     => 'Log::Dispatch::File',
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my $self = shift;
        my $output = Log::Dispatch::File->new(
            name      => 'everything',
            min_level => $self->_default_min_level,
            filename  => logfile_for("everything"),
            callbacks => sub { $self->_format(@_) },
        );
        $self->add_as_default($output);
        return $output;
    },
);

has warning => (
    isa     => 'Log::Dispatch::File',
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my $self = shift;
        my $output = Log::Dispatch::File->new(
            name      => 'warning',
            min_level => 'warning',
            filename  => logfile_for("warning"),
            callbacks => sub { $self->_format(@_) },
        );
        $self->add_as_default($output);
        return $output;
    },
);

has error => (
    isa     => 'Log::Dispatch::File',
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my $self = shift;
        my $output = Log::Dispatch::File->new(
            name      => 'error',
            min_level => 'error',
            filename  => logfile_for("error"),
            callbacks => sub { $self->_format(@_) },
        );
        $self->add_as_default($output);
        return $output;
    },
);

has twitter => (
    isa     => 'Maybe[Log::Dispatch::Twitter]',
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return unless $self->config;
        my $error_config = $self->config->{twitter}{errors};
        return unless $error_config;
        require Log::Dispatch::Twitter;
        my $twitter = Log::Dispatch::Twitter->new(
            name      => 'twitter',
            min_level => 'error',
            username  => $error_config->{username},
            password  => $error_config->{password},
            callbacks => sub {
                my %args = @_;
                return if $args{message} =~ /^Game over/;

                # XXX: we need to not throw errors when we die
                return if $args{message} =~ /^Unable to parse the (botl|status)/;

                $args{message} =~ s/\n.*//s;
                return sprintf "%s (T%s): %s",
                            TAEB->loaded_persistent_data
                          ? (TAEB->name, TAEB->turn)
                          : ('?',        '-'       ),
                            $args{message};
            },
        );
        $self->add_as_default($twitter);
        return $twitter;
    },
);

around new => sub {
    my $orig = shift;
    my $self = $orig->(@_);
    # we don't initialize log files until they're used, so need to make sure
    # old ones don't stick around
    $self->_clean_log_dir;
    $self->everything;
    $self->warning;
    $self->error;
    $self->twitter;
    return $self;
};

around twitter => sub {
    my $orig = shift;
    my $self = shift;
    my $output = $self->$orig();
    return $output unless @_;
    my $message = shift;
    $output->log(level => 'error', message => $message, @_);
};

around [qw/everything warning error/] => sub {
    my $orig = shift;
    my $self = shift;
    die "Don't log directly to the catch-all loggers" if @_;
    return $self->$orig();
};

after add_channel => sub {
    my $self = shift;
    my $channel_name = shift;

    for my $output (@{ $self->default_outputs }) {
        $self->channel($channel_name)->add($output);
    }
};

our $AUTOLOAD;
sub AUTOLOAD {
    my $self = shift;
    my $message = shift;
    my $channel_name = $AUTOLOAD;
    $channel_name =~ s/.*:://;
    return unless $self->_should_log($channel_name);
    my $channel = $self->channel($channel_name);
    if (!$channel) {
        # XXX: would be nice if LDC had global callbacks
        $self->add_channel($channel_name,
                           callbacks => [
                           sub {
                               my %args = @_;
                               if ($self->bt_levels->{$args{level}}) {
                                   return Carp::longmess($args{message});
                               }
                               else {
                                   return $args{message};
                               }
                           },
                           sub {
                               my %args = @_;
                               return sprintf "[%s:%s] %s",
                                              uc($args{level}),
                                              $channel_name,
                                              $args{message};
                           },
                           ]);
        $self->add(Log::Dispatch::File->new(
                       name      => $channel_name,
                       min_level => $self->_default_min_level,
                       filename  => logfile_for($channel_name),
                       callbacks => sub { $self->_format(@_) },
                   ),
                   channels => $channel_name);
    }
    $self->log(channels => $channel_name,
               level    => 'debug',
               message  => $message,
               @_);
}

sub add_as_default {
    my $self = shift;
    my $output = shift;

    $self->add($output);
    push @{ $self->default_outputs }, $output;
}

sub _format {
    my $self = shift;
    my %args = @_;

    chomp $args{message};

    my ($sec, $min, $hour, $mday, $mon, $year) = localtime;

    return sprintf "<T%s> %04d-%02d-%02d %02d:%02d:%02d %s\n",
                   (TAEB->loaded_persistent_data ? TAEB->turn : '-'),
                   $year + 1900,
                   $mon + 1,
                   $mday,
                   $hour,
                   $min,
                   $sec,
                   $args{message};
}

sub _default_min_level {
    my $self = shift;
    my $log_config = $self->config;
    return 'debug' unless defined $log_config
                       && exists  $log_config->{min_level};
    return $log_config->{min_level};
}

sub _should_log {
    my $self = shift;
    my ($channel) = @_;
    # don't treat DEMOLISH as a logging call, etc
    return if $channel =~ /^[A-Z_]+$/;
    my $log_config = $self->config;
    if (defined $log_config && exists $log_config->{suppress}) {
        my $suppression = $log_config->{suppress};
        if (ref($suppression) eq 'ARRAY') {
            return if grep { !$self->_should_log($_) } @$suppression;
        }
        elsif ($suppression =~ s{^/(.*)/$}{$1}) {
            return if $channel =~ /$suppression/;
        }
        else {
            return if $channel eq $suppression;
        }
    }
    return 1;
}

sub _maybe_create_dir {
    my $dir = shift;
    my $dir_reason = shift;
    if (!-d $dir && !mkdir $dir) {
        warn "Please make a writable $dir_reason directory at $dir";
        return 0;
    }
    return 1;
}

sub logfile_for {
    my $channel = shift;

    # if we can't open or create the logdir, then just put logs into the current
    # directory :/
    my $logdir = TAEB->config->taebdir_file("log");
    return "TAEB-$channel.log" unless _maybe_create_dir($logdir, "log file");
    return TAEB->config->taebdir_file("log", "$channel.log");
}

sub _creation_time {
    open my $everything, "<", logfile_for("everything");
    my $start_line = <$everything>;
    $start_line =~ s/^<T-> (\S+ \S+).*/$1/;
    $start_line =~ /(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/;
    return ($1, $2, $3, $4, $5, $6);
}

sub _backup_logs {
    my $self = shift;
    my ($config) = @_;

    return unless _maybe_create_dir(TAEB->config->taebdir_file($config->{dir}),
                                    "log rotate");

    my ($year, $mon, $mday, $hour, $min, $sec) = $self->_creation_time;
    my $timestamp = sprintf "%04d%02d%02d%02d%02d%02d", $year, $mon, $mday,
                                                        $hour, $min, $sec;

    my $compress = $config->{compress};
    require File::Copy;
    require IO::Compress::Gzip if $compress;
    for my $file (glob logfile_for('*')) {
        (my $backup = $file) =~ s{(?:.*/)?(.*?)}{$1};
        $backup = TAEB->config->taebdir_file($config->{dir},
                                             "$backup.$timestamp");
        File::Copy::copy($file, $backup);
        if ($compress) {
            IO::Compress::Gzip::gzip($backup => "$backup.gz");
            unlink $backup;
        }
    }
}

before _clean_log_dir => sub {
    my $self = shift;
    return unless -d TAEB->config->taebdir_file("log");
    return unless defined $self->config;
    my $log_rotate_config = $self->config->{log_rotate};
    return unless $log_rotate_config && $log_rotate_config->{dir};
    $self->_backup_logs($log_rotate_config);
};
sub _clean_log_dir {
    unlink for (glob logfile_for('*'));
}

# we need to use Log::Dispatch::Channels' constructor
__PACKAGE__->meta->make_immutable(inline_constructor => 0);
no TAEB::OO;

1;
