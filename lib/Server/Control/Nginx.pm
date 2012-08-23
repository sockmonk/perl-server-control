package Server::Control::Nginx;
use Cwd qw(realpath);
use File::Spec::Functions qw(catfile);
use Log::Any qw($log);
use Moose;
use strict;
use warnings;

extends 'Server::Control';

has '+binary_name' => ( is => 'ro', isa => 'Str', default => 'nginx' );
has 'conf_file'    => ( is => 'ro', required => 1 );

sub BUILD {
    my ($self) = @_;

    $self->_validate_conf_file();
}

sub do_start {
    my $self = shift;
    $self->check_conf_syntax();
    $self->run_system_command(
        sprintf( '%s -c %s', $self->binary_path, $self->conf_file ) );
}

sub do_stop {
    my $self = shift;

    $self->run_system_command(
        sprintf( '%s -c %s -s stop', $self->binary_path, $self->conf_file ) );
}

sub _validate_conf_file {
    my ($self) = @_;
    # Ensure that we have an existent conf_file after object is built.
    if ( my $conf_file = $self->{conf_file} ) {
        die "no such conf file '$conf_file'" unless -f $conf_file;
        $self->{conf_file} = realpath($conf_file);
    }
}

sub _build_pid_file {
    my $self = shift;
    my $pid_file;
    if ($self->log_dir && ( -d $self->log_dir )) {
        $log->debugf( "defaulting pid_file to %s/%s",
                      $self->log_dir, "nginx.pid" )
            if $log->is_debug;
        $pid_file = catfile( $self->log_dir, "nginx.pid" );
    }
    return $pid_file;
}

sub _build_bind_addr {
    my $self = shift;
    $log->debugf("defaulting bind_addr to localhost") if $log->is_debug;
    return 'localhost';
}

override 'hup' => sub {
    my $self = shift;
    $self->check_conf_syntax();
    super();
};

sub check_conf_syntax {
    my $self         = shift;
    my $binary_name = $self->binary_name();
    my $conf_file    = $self->conf_file();
    # Nginx uses the -q flag to suppress 'ok' messages
    my $cmd          = sprintf( '%s -t -q -c %s', $binary_name, $conf_file );

    $self->run_system_command($cmd);
}

sub graceful {
    my $self = shift;

    my $proc = $self->is_running()
      || return $self->start();
    $self->_warn_if_different_user($proc);
    $self->check_conf_syntax();

    my $error_size_start = $self->_start_error_log_watch();

    eval { $self->run_nginx_command('graceful') };
    if ( my $err = $@ ) {
        $log->errorf( "error during graceful restart of %s: %s",
            $self->description(), $err );
    }

    if (
        $self->_wait_for_status(
            Server::Control::ACTIVE(), 'graceful restart'
        )
      )
    {
        $log->info( $self->status_as_string() );
        if ( $self->validate_server() ) {
            $self->successful_start();
            return 1;
        }
    }
    $self->_report_error_log_output($error_size_start);
    return 0;
}

sub graceful_stop {
    my $self = shift;

    $self->stop_cmd('graceful-stop');
    $self->stop();
}


sub run_nginx_command {
    my ( $self, $command ) = @_;

    my $nginx_binary = $self->nginx_binary();
    my $conf_file    = $self->conf_file();

    my $cmd = "$nginx_binary -c $conf_file";
    if ($command eq "start") {
        # no change
    }
    elsif ($command eq "reload") {
        $cmd .= " -s reload";
    }
    elsif ($command eq "stop") {
        $cmd .= " -s stop";
    }
    elsif ($command eq "quit") {
        $cmd .= " -s quit";
    }
    elsif ($command eq "configtest") {
        $cmd .= " -t";
    }
    elsif ($command eq "reopen-log") {
        $cmd .= " -s reopen";
    }
    elsif ($command eq 'status') {
        $log->info($self->status_as_string());
        return;
    }
    else {
        die "unknown command: $command";
    }
    $self->run_system_command($cmd);
}


__PACKAGE__->meta->make_immutable();

1;

__END__

=pod

=head1 NAME

Server::Control::Nginx -- Control Nginx

=head1 SYNOPSIS

    use Server::Control::Nginx;

    my $nginx = Server::Control::Nginx->new(
        binary_path => '/usr/sbin/nginx',
        conf_file => '/path/to/nginx.conf'
    );
    if ( !$nginx->is_running() ) {
        $nginx->start();
    }

=head1 DESCRIPTION

Server::Control::Nginx is a subclass of L<Server::Control|Server::Control> for
L<Nginx|http://nginx.org/> processes.

=head1 CONSTRUCTOR

In addition to the constructor options described in
L<Server::Control|Server::Control>:

=over

=item conf_file

Path to conf file - required.

=back

=head1 METHODS

The following methods are supported in addition to those described in
L<Server::Control|Server::Control>:

=over

=item graceful

If the server is not running, then start it. Otherwise, gracefully restart
the server. You can assign this to L<Server::Control/restart_method>.

=item graceful_stop

Gracefully stop the server.

=item check_conf_syntax

Check the given nginx conf file for syntax issues. Silent if no errors are found.

=item do_start

Check the conf syntax and start the server.

=item do_stop

Stop the server.

=item run_nginx_command

Runs the expected commands, though many of them are implemented by sending a
signal to the nginx process.

=item status

Show the server's current status.

=back


=head1 SEE ALSO

L<Server::Control|Server::Control>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Jonathan Swartz.

This is free software; you can redistribute it and/or modify it under the same
terms as the Perl 5 programming language system itself.

=cut
