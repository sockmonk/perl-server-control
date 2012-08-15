#!perl

use Test::More tests => 3;

BEGIN {
    use_ok('Server::Control');
    use_ok('Server::Control::Apache');
    use_ok('Server::Control::Nginx');
}

diag("Testing Server::Control $Server::Control::VERSION, Perl $], $^X");
