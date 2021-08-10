use strict;
use warnings;
use JSON::PP;

use DBI qw(:utils);

use Zonemaster::Backend::Config;
use Zonemaster::Backend::DB::SQLite;

my $config = Zonemaster::Backend::Config->load_config();
if ( $config->DB_engine ne 'SQLite' ) {
    die "The configuration file does not contain the SQLite backend";
}
my $db = Zonemaster::Backend::DB::SQLite->from_config( $config );
my $dbh = $db->dbh;


sub patch_db {

    # Rename column "params_deterministic_hash" into "fingerprint"
    # Since SQLite 3.25 (2018-09-15) <https://sqlite.org/changes.html>
    eval {
        $dbh->do('ALTER TABLE test_results RENAME COLUMN params_deterministic_hash TO fingerprint');
    };
    print( "Error while changing DB schema:  " . $@ ) if ($@);

    # Update index
    eval {
        $dbh->do( "DROP INDEX IF EXISTS test_results__params_deterministic_hash ON test_results" );
        $dbh->do( "CREATE INDEX test_results__fingerprint ON test_results (fingerprint)" );
    };
    print( "Error while updating the index:  " . $@ ) if ($@);

    # Update the "undelegated" column
    my $sth1 = $dbh->prepare('SELECT id, params from test_results', undef);
    $sth1->execute;
    while ( my $row = $sth1->fetchrow_hashref ) {
        my $id = $row->{id};
        my $raw_params = decode_json($row->{params});
        my $ds_info_values = scalar grep !/^$/, map { values %$_ } @{$raw_params->{ds_info}};
        my $nameservers_values = scalar grep !/^$/, map { values %$_ } @{$raw_params->{nameservers}};
        my $undelegated = $ds_info_values > 0 || $nameservers_values > 0 || 0;

        $dbh->do('UPDATE test_results SET undelegated = ? where id = ?', undef, $undelegated, $id);
    }
}

patch_db();
