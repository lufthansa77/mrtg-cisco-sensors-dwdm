# Cisco DWDM sensors - mrtg module  v0.1 - 3.10.2017   DC
#
# INSTALL
#    cpanm RRDTool::OO
#    cfgmaker --host-template=cisco-sensors-dwdm.pl

# hack skrze rrd_tune aby to umelo zaporna cisla
# je potreba to pustit a pak jeste pockat a pustit to znovu
#
#  rrdtool info test.rrd |grep ds
#  rrdtool tune test.rrd --minimum ds0:-100
#

use constant c_oid_ifName => '1.3.6.1.2.1.31.1.1.1.1';    # ifName  (podle nazvu dwdm zjistime indexy jen dwdm interfaces)

#RP/0/RP0/CPU0:ROUTER-CO2# sh snmp interface | i dwdm
# snmpwalk -v2c -c clandestine  router-co2  .1.3.6.1.4.1.9.9.639

#You'll get the final value of pre-FEC BER using simple arithmetic operation (MRTG syntax):
#Mantissa * 10 ** Exponent

# CISCO-OTN-IF-MIB
use constant c_oid_coiIfControllerPreFECBERMantissa => '1.3.6.1.4.1.9.9.639.1.1.1.1.10';
use constant c_oid_coiIfControllerPreFECBERExponent => '1.3.6.1.4.1.9.9.639.1.1.1.1.11';
use constant c_oid_coiIfControllerQFactor           => '1.3.6.1.4.1.9.9.639.1.1.1.1.12';
use constant c_oid_IfControllerQMargin              => '1.3.6.1.4.1.9.9.639.1.1.1.1.13';

my $sensors  = undef;
my @ifname   = ( snmpwalk( $router, $v3opt, c_oid_ifName ) );
my @mantissa = ( snmpwalk( $router, $v3opt, c_oid_coiIfControllerPreFECBERMantissa ) );
my @exponent = ( snmpwalk( $router, $v3opt, c_oid_coiIfControllerPreFECBERExponent ) );
my @q        = ( snmpwalk( $router, $v3opt, c_oid_coiIfControllerQFactor ) );
my @qmargin  = ( snmpwalk( $router, $v3opt, c_oid_IfControllerQMargin ) );

sub save_to_hash {    # {{{
    my ( $arry, $key ) = @_;

    foreach my $line (@$arry) {
        my ( $index, $value ) = split( /:/, $line, 2 );
        $sensors->{$index}->{$key} = $value;
    }
}    # }}}

save_to_hash( \@ifname,   'ifName' );
save_to_hash( \@mantissa, 'coiIfControllerPreFECBERMantissa' );
save_to_hash( \@exponent, 'coiIfControllerPreFECBERExponent' );
save_to_hash( \@q,        'coiIfControllerQFactor' );
save_to_hash( \@qmargin,  'IfControllerQMargin' );

foreach my $index ( keys %{$sensors} ) {    # vycistime interfaces ktere nejsou dwdm
    if ( $sensors->{$index}{ifName} !~ /^dwdm.+/ ) {
        delete $sensors->{$index};
    }
}

foreach my $index ( keys %{$sensors} ) {    # vycistime interfaces ktere nejsou dwdm

    my $mantissa = $sensors->{$index}{coiIfControllerPreFECBERMantissa};
    my $exponent = $sensors->{$index}{coiIfControllerPreFECBERExponent};
    $sensors->{$index}{preFECBER} = $mantissa * 10**$exponent;

    my $qmargin = $sensors->{$index}{IfControllerQMargin};
    $sensors->{$index}->{Qmargin} = $qmargin / 100;

    my $qfactor = $sensors->{$index}{coiIfControllerQFactor};
    $sensors->{$index}->{Q} = $qfactor / 100;
}

#use Data::Dump qw(pp);
#pp($sensors);

#  395 => {
#           IfControllerQMargin => 498,
#           Q => "4.63",
#           Qmargin => "4.98",
#           "coiIfControllerPreFECBERExponent" => -6,
#           "coiIfControllerPreFECBERMantissa" => 221,
#           "coiIfControllerQFactor" => 463,
#           ifName => "dwdm0/8/0/20/0",
#           preFECBER => "0.000221",
#         },
#pp($router_opt); #{{{
#{
#  "enable-ipv6"   => 0,
#  enablesnmpv3    => 0,
#  global          => [
#                       "WorkDir: /var/www/html/north.hebe.cz/mrtg",
#                       "Options[_]: bits,growright,nobanner",
#                       "14all*DontShowIndexGraph[_]: Yes",
#                       "14all*Columns: 1",
#                       "LogFormat: rrdtool",
#                     ],
#  "host-template" => "cisco-sensors.pl",
#  ifdesc          => "name",
#  interfaces      => 1,
#  "show-op-down"  => 1,
#  "use-16bit"     => 0,
#} # }}}

sub return_workdir {    # {{{
    my %h = ();

    foreach my $line ( @{ $router_opt->{global} } ) {
        my ( $key, $value ) = split( /:/, $line, 2 );
        $h{$key} = $value;
    }
    return ( $h{WorkDir} );
}    # }}}

my $work_dir = return_workdir();

foreach my $index ( sort keys %{$sensors} ) {

    my @words = ( 'Q', 'Qmargin', 'preFECBER' );

    foreach my $word (@words) {
        my $oid  = undef;
        my $name = $word;
        my $value     = $sensors->{$index}->{$word};

        my $interface = $sensors->{$index}->{ifName};
        $interface =~ s/\//_/g;

        my $file_name = $router_name . "_dwdm_" . $interface . "_" . $word;

        # rrd_tune hack pro zaporna cisla:
        my $rrd_file_name = $work_dir . "/" . $file_name . ".rrd";
        $rrd_file_name =~ s/^\s+//;
        if ( -e $rrd_file_name ) {    #pokud uz sensor file existuje nastavime soubor i na zaporna cisla
            use RRDTool::OO;
            my $rrd = RRDTool::OO->new( file => "$rrd_file_name" );
            $rrd->tune( dsname => 'ds0', minimum => -10000000 );
            $rrd->tune( dsname => 'ds1', minimum => -10000000 );
        }

        $target_lines .= "# Sensor $interface $word (SNMP ifName: $index)\n";

        if ( $word eq 'Q' ) {
            $oid = c_oid_coiIfControllerQFactor . '.' . $index;
            $target_lines .= "Target[$file_name]: $oid&$oid:$router_connect /100\n";
        }
        if ( $word eq 'Qmargin' ) {
            $oid = c_oid_IfControllerQMargin . '.' . $index;
            $target_lines .= "Target[$file_name]: $oid&$oid:$router_connect /100\n";
        }
        if ( $word eq 'preFECBER' ) {
            $oid = c_oid_IfControllerQMargin . '.' . $index;
            my $oid_mantissa = c_oid_coiIfControllerPreFECBERMantissa . '.' . $index;
            my $oid_exponent = c_oid_coiIfControllerPreFECBERExponent . '.' . $index;
            $target_lines .= "Target[$file_name]: $oid_mantissa&$oid_mantissa:$router_connect * 10 ** $oid_exponent&$oid_exponent:$router_connect\n";
        }

        $target_lines .= <<ECHO
SnmpOptions[$file_name]: $v3options
Options[$file_name]: gauge,growright,nopercent
Legend1[$file_name]: $name
Legend2[$file_name]: $name
Legend3[$file_name]: Peak $name
Legend4[$file_name]: Peak $name
LegendI[$file_name]: $name
LegendO[$file_name]: $name
YLegend[$file_name]: $name
MaxBytes[$file_name]: 10000000
Directory[$file_name]: $directory_name
ShortLegend[$file_name]: $name
WithPeak[$file_name]: ymw
Title[$file_name]: $name
TimeStrFmt[$file_name]: %H:%M:%S
PageTop[$file_name]: <h2>$sysname</h2>
   <div><table><tr>
          <td>Sensor:</td>
          <td>$interface - $name (SNMP ifName: $index)</td>
     </tr></table></div>
ECHO
          ;
    }
}
