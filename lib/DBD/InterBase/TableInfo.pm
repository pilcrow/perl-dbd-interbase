use strict;

package DBD::InterBase::TableInfo;

sub factory {
    my (undef, $dbh) = @_;
    my ($vers, $klass);

    my $vers = $dbh->func('version', 'ib_database_info')->{version};

    $dbh->trace_msg("TableInfo factory($dbh [$vers])");

    if ($vers =~ /firebird (\d\.\d+)/i and $1 >= 2.1) {
        $klass = 'DBD::InterBase::TableInfo::Firebird21';
    } else {
        $klass = 'DBD::InterBase::TableInfo::Basic';
    }

    eval "require $klass";
	die $@ if $@;
    $klass->new() if $klass;
}

1;
