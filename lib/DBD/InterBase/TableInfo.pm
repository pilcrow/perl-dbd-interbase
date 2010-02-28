use strict;

package DBD::InterBase::TableInfo::Basic;

=head1 NAME

DBD::InterBase::TableInfo::Basic - A base class for lowest-common denominator Interbase table_info() querying.

=head1 SYNOPSIS

    package DBD::InterBase::TableInfo::SpecificIBVersion;
    @ISA = qw(DBD::InterBase::TableInfo::Basic);

    sub supported_types {
        ('SYSTEM TABLE', 'TABLE', 'VIEW', 'SPECIAL TABLE TYPE');
    }

    sub table_info {
        my ($self, $dbh, $table, @types) = @_;
    }

=head1 INTERFACE

=over 4

=item I<list_catalogs>

    $tbl_info->list_catalogs($dbh);

Called in response to $dbh->table_info('%', '', ''), returning an empty
statement handle.  (Rule 19a)

=item I<list_schema>

    $tbl_info->list_schema($dbh);

Called in response to $dbh->table_info('', '%', ''), returning an empty
statement handle.  (Rule 19b)

=item I<list_tables>

    $tbl_info->list_tables($dbh, $table, @types);

Called in response to $dbh->table_info($cat, $schem, $table, $types).  C<$cat>
and C<$schem> are presently ignored, as no IB/FB derivative supports the DBI
notion of catalogs and schema.

This is the workhorse method that must return an appropriate statement handle
of tables given the requested C<$table> pattern and C<@types>.  A blank
C<$table> pattern means "any table," and an empty C<@types> list means "any
type."

C<@types> is a list of user-supplied, requested types.
C<DBD::InterBase::db::table_info> will normalize the user-supplied types,
stripping quote marks, uppercasing, and removing duplicates.

=item I<list_types>

    $tbl_info->list_types($dbh);

Called in response to $dbh->table_info('', '', '', '%'), returning a
statement handle with a TABLE_TYPE column populated with the results of
I<supported_types>.  (Rule 19c)

Normally not overridden.  Override I<supported_types>, instead.

=item I<supported_types>

    $tbl_info->supported_types($dbh);

Returns a list of supported DBI TABLE_TYPE entries.  The default
implementation supports 'TABLE', 'SYSTEM TABLE' and 'VIEW'.

=back

=cut

# Good grief.  Without CASE/END and without derived tables we stitch
# together a UNION'd query covering all our possible
#
# TRIM() would be useful because RDB$RELATION_NAME may be padded, and in
# strict SQL, 'foo   ' NOT LIKE 'foo'.  That's fine for SQL, but confusing
# for the hapless programmer who's merely looking for a list of table names
# against a SQL pattern.
#

my %IbTableTypes = (
  # We ignore the hypothetical (unimplemented in practice?) 'SYSTEM VIEW'
  'SYSTEM TABLE' => '(rdb$system_flag = 1)',
         'TABLE' => '((rdb$system_flag = 0 OR rdb$system_flag IS NULL) AND rdb$view_blr IS NULL)',
          'VIEW' => '((rdb$system_flag = 0 OR rdb$system_flag IS NULL) AND rdb$view_blr IS NOT NULL)',
);

sub supported_types {
    sort keys %IbTableTypes;
}

sub sponge {
    # no warnings 'once';
    my ($self, $dbh, $stmt, $attrib_hash) = @_;
    my $sponge = DBI->connect('dbi:Sponge:', '', '')
                   or return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr");
    return ($sponge->prepare($stmt, $attrib_hash)
            or
            $dbh->DBI::set_err($sponge->err(), $sponge->errstr()));
}

sub list_catalogs {
	my ($self, $dbh) = @_;
	return $self->sponge($dbh, 'catalog_info', {
            NAME => [qw(TABLE_CAT TABLE_SCHEM TABLE_NAME TABLE_TYPE REMARKS)],
            rows => [],
        });
}

sub list_schema {
	my ($self, $dbh) = @_;
	$self->sponge($dbh, 'schema_info', {
        NAME => [qw(TABLE_CAT TABLE_SCHEM TABLE_NAME TABLE_TYPE REMARKS)],
        rows => [],
    });
}

sub list_types {
    my ($self, $dbh) = @_;
    my @rows = map { [undef, undef, undef, $_, undef] } $self->supported_types;
    $self->sponge($dbh, 'supported_type_info', {
        NAME => [qw(TABLE_CAT TABLE_SCHEM TABLE_NAME TABLE_TYPE REMARKS)],
        rows => \@rows
    });
}

sub table_info {
    my ($self, $dbh, $name, @types) = @_;
    my %selects = (); # @types is guar. to be unique already, but we use
                      # this hash to weed our duplicate '_unknown_' types

    $name = '%' unless length($name);
    @types = keys %IbTableTypes unless @types;

	for (@types) {
        my ($name, $where) = exists $IbTableTypes{$_} ?
                             ($_, $IbTableTypes{$_} ) :
                             ('_unknown_', '1=0')     ; # <-- guaranteed 0 rows

        $selects{$name} ||= <<__eosql;
SELECT CAST(NULL AS CHAR(1))     AS TABLE_CAT,
       CAST(NULL AS CHAR(1))     AS TABLE_SCHEM,
       rdb\$relation_name        AS TABLE_NAME,
       CAST('$name' AS CHAR(15)) AS TABLE_TYPE,
       rdb\$description          AS REMARKS,
       rdb\$owner_name           AS ib_owner_name
  FROM rdb\$relations
 WHERE ($where)
         AND
       rdb\$relation_name LIKE ?
__eosql
    }

    local $dbh->{ChopBlanks} = 1;
    my $sth = $dbh->prepare(join "\nUNION\n" => values %selects);
    if ($sth) {
        $sth->execute( ($name,) x scalar(keys %selects) );
    }
    return $sth;
}

# fb 1.5 CASE, COALESCE
# fb 2.0 TRIM(), derived tables
# fb 2.1 rdb$relations.rdb$relation_type
#        0 persistent
#        1 view
#        2 external
#        3 virtual
#        4 global temporary preserve
#        5 global temporary delete

# Firebird 2.1

package DBD::InterBase::TableInfo::Firebird21;
use vars qw(@ISA);
@ISA = qw(DBD::InterBase::TableInfo::Basic);

my %FbTableTypes = (
    'SYSTEM TABLE' => '(rdb$system_flag = 1)',
           'TABLE' => '((rdb$system_flag = 0 OR rdb$system_flag IS NULL) AND rdb$view_blr IS NULL)',
            'VIEW' => '((rdb$system_flag = 0 OR rdb$system_flag IS NULL) AND rdb$view_blr IS NOT NULL)',
'GLOBAL TEMPORARY' => '((rdb$system_flag = 0 OR rdb$system_flag IS NULL) AND rdb$relation_type IN (4, 5))',
);

sub supported_types {
    sort keys %FbTableTypes;
}

sub table_info {
    my ($self, $dbh, $table, @types) = @_;
    my (@conditions, @bindvars);

    if (length $table) {
        push @conditions, 'TRIM(TABLE_NAME) LIKE ?';
        push @bindvars, $table;
    }

    push @conditions, join ' OR ' => map { $FbTableTypes{$_} || '1=0' } @types;

    my $where = @conditions                           ?
                'WHERE ' . join(' AND ', @conditions) :

    # "The Firebird System Tables Exposed"
    # Martijn Tonies, 6th Worldwide Firebird Conference 2008
    # Bergamo, Italy
    local $dbh->{ChopBlanks};
    return $dbh->prepare(<<__eosql)
  SELECT NULL                    AS TABLE_CAT,
         NULL                    AS TABLE_SCHEM,
         rdb\$relation_name      AS TABLE_NAME,
         CASE
           WHEN rdb\$system_flag > 0         THEN 'SYSTEM TABLE'
           WHEN rdb\$view_blr IS NOT NULL    THEN 'VIEW'
           WHEN rdb\$relation_type IN (4, 5) THEN 'GLOBAL TEMPORARY'
           ELSE 'TABLE'
         END                      AS TABLE_TYPE,
         rdb\$description         AS REMARKS,
         rdb\$owner_name          AS ib_owner_name,
         rdb\$external_file       AS ib_external_file,
         CASE rdb\$relation_type
           WHEN 0 THEN 'Persistent'
           WHEN 1 THEN 'View'
           WHEN 2 THEN 'External'
           WHEN 3 THEN 'Virtual'
           WHEN 4 THEN 'Global Temporary Preserve'
           WHEN 5 THEN 'Global Temporary Delete'
           ELSE        NULL
         END                      AS ib_relation_type
    FROM rdb\$relations
) d $where
__eosql
}

__END__
sub fb15_table_info {
  SELECT NULL                     AS TABLE_CAT,
         NULL                     AS TABLE_SCHEM,
         TRIM(rdb\$relation_name) AS TABLE_NAME,
         CASE
           WHEN rdb\$system_flag > 0 THEN 'SYSTEM TABLE'
           WHEN rdb\$view_blr IS NOT NULL THEN 'VIEW'
           ELSE 'TABLE'
         END                      AS TABLE_TYPE,
         rdb\$description         AS REMARKS,
         rdb\$owner_name          AS ib_owner_name,
         rdb\$external_file       AS ib_external_file
    FROM rdb\$relations
}
# vim:set et ts=4:
