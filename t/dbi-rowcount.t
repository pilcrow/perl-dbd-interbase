#! env perl

# dbi-rowcount.t
#
# Verify behavior of interfaces which report number of rows affected

use strict;
use Test::More tests => 66;
use DBI;
use vars qw($dbh $table);

BEGIN {
	# $::test_dsn, FindNewTable, etc.
	for ("lib.pl", "t/lib.pl") {
		last if do $_;
		die "Error compiling lib.pl: $@" if $@;
	}
}
END {
	if (defined $dbh and defined $table) {
		eval { $dbh->do("DROP TABLE $table"); };
	}
}

# is() with special case "zero but true" support
sub is_maybe_zbt {
	my ($value, $expected, $msg) = @_;
	return is($value, $expected, $msg) unless $expected == 0;

	$msg = join(' ', $msg, '(zero but true)');
	return ok(($value == 0 and $value), $msg);
}

# == Test Initialization =========================================

$dbh = DBI->connect($::test_dsn, $::test_user, $::test_password,
                    {RaiseError => 1});
pass("connect($::test_dsn)");
$table = FindNewTable($dbh);
$dbh->do("CREATE TABLE $table(ID INTEGER NOT NULL, NAME VARCHAR(16) NOT NULL)");
pass("CREATE TABLE $table");

my @TEST_PROGRAM = (
	{
		sql      => qq|INSERT INTO $table (ID, NAME) VALUES (1, 'unu')|,
		desc     => 'literal insert',
		expected => 1,
	},
	{
		sql      => qq|INSERT INTO $table (ID, NAME) VALUES (?, ?)|,
		desc     => 'parameterized insert',
		params   => [2, 'du'],
		expected => 1,
	},
	{
		sql      => qq|DELETE FROM $table WHERE 1=0|,
		desc     => 'DELETE WHERE (false)',
		expected => 0,
	},
	{
		sql      => qq|UPDATE $table SET NAME='nomo'|,
		desc     => 'UPDATE all',
		expected => 2,
	},
	{
		sql      => qq|DELETE FROM $table|,
		desc     => 'DELETE all',
		expected => 2,
	},
);

# == Tests ==

# == 1. do()

for my $spec (@TEST_PROGRAM) {
	my @bind = @{$spec->{params}} if $spec->{params};
	my $rv = $dbh->do($spec->{sql}, undef, @bind);

	is_maybe_zbt($rv, $spec->{expected}, "do($spec->{desc})");
	is_maybe_zbt($DBI::rows, $spec->{expected}, "do($spec->{desc}) (\$DBI::rows)");
}

# == 2a. single execute() and rows()

for my $spec (@TEST_PROGRAM) {
	my @bind = @{$spec->{params}} if $spec->{params};
	my $sth = $dbh->prepare($spec->{sql});
	my $rv = $sth->execute(@bind);

	is_maybe_zbt($rv, $spec->{expected}, "execute($spec->{desc})");
	is_maybe_zbt($DBI::rows, $spec->{expected}, "execute($spec->{desc}) (\$DBI::rows)");
	is_maybe_zbt($sth->rows, $spec->{expected}, "\$sth->rows($spec->{desc})");
}

# == 2b. repeated execute() and rows()
{
	my $i = 0;
	my $sth = $dbh->prepare("INSERT INTO $table(ID, NAME) VALUES (?, ?)");
	for my $name (qw|unu du tri kvar kvin ses sep ok naux dek|) {
		my $rv = $sth->execute(++$i, $name);
		is($rv, 1, "re-execute(INSERT one) -> 1");
		is($DBI::rows, 1, "re-execute(INSERT one) -> 1 (\$DBI::rows)");
		is($sth->rows, 1, "\$sth->rows(re-executed INSERT)");
	}

	$sth = $dbh->prepare("DELETE FROM $table WHERE ID<?");
	for (6, 11) {
		my $rv = $sth->execute($_);
		is($rv, 5, "re-execute(DELETE five) -> 1");
		is($DBI::rows, 5, "re-execute(DELETE five) -> 1 (\$DBI::rows)");
		is($sth->rows, 5, "\$sth->rows(re-executed DELETE)");
	}
	my $rv = $sth->execute(16);
	is_maybe_zbt($rv, "re-execute(DELETE on empty)");
	is_maybe_zbt($DBI::rows, "re-execute(DELETE on empty) (\$DBI::rows)");
	is_maybe_zbt($sth->rows, "\$sth->rows(re-executed DELETE on empty)");
}

# == 3. special cases
#       DBD::InterBase tracks the number of FETCHes on a SELECT statement
#       in $rows as an extension to the DBI.

{
	my $i = 0;
	for my $name (qw|unu du tri kvar kvin ses sep ok naux dek|) {
		$dbh->do("INSERT INTO $table(ID, NAME) VALUES (?, ?)", undef, ++$i, $name);
	}
	my $sth = $dbh->prepare("SELECT ID, NAME FROM $table");
	my $rv = $sth->execute;
	zbt($rv, "execute(SELECT) -> zero but true");
	zbt($DBI::rows, "execute(SELECT) zero but true (\$DBI::rows)");
	zbt($sth->rows, "\$sth->rows(SELECT) zero but true");

	my $fetched = 0;
	while ($sth->fetch) {
		is(++$fetched, $sth->rows, "\$sth->rows incrementing on SELECT");
		is($fetched, $DBI::rows, "\$DBI::rows incrementing on SELECT");
	}
}
