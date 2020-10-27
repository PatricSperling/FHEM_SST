################################################################################
# 48_SST.pm
#   Version 0.7.22 (2020-10-27)
#
# SYNOPSIS
#   Samsung SmartThings Connecton Module for FHEM
#
# DESCRIPTION
#   This module connects to the Samsung SmartThings cloud service and
#    - manages the creation of the Samsung SmartThings devices in FHEM,
#    - gets the status of created FHEM devices and
#    - sets/controls these devices.
#   For details please refer to the inline documentation.
#   This module is loosely based on an older, but more limited implementation
#   by Sebastian Siepmann (48_Smartthings.pm).
#
# AUTHOR
#   Patric Sperling (https://forum.fhem.de)
#
################################################################################

package main;
use strict;
use warnings;

# predefine some variables
my $SST_missing_modules = '';

#package SmartThingsFridge;
#use strict;
#use warnings;
eval "use Encode qw(encode_utf8);1" or $SST_missing_modules .= ' Encode';
eval "use HTTP::Request ()      ;1" or $SST_missing_modules .= ' HTTP::Request';
eval "use JSON                  ;1" or $SST_missing_modules .= ' JSON';
eval "use LWP::UserAgent        ;1" or $SST_missing_modules .= ' LWP::UserAgent';
eval "use Data::Dumper          ;1" or $SST_missing_modules .= ' Data::Dumper';

$Data::Dumper::Indent   = 1;
$Data::Dumper::Useqq    = 1;
$Data::Dumper::Sortkeys = 1;

#####################################
# INITIALIZATION
sub SST_Initialize($) {
    my ($hash) = @_;
    $hash->{DefFn}       = 'SST_Define';
    $hash->{UndefFn}     = 'SST_Undefine';
    $hash->{SetFn}       = 'SST_Set';
    $hash->{GetFn}       = 'SST_Get';
    $hash->{NotifyFn}    = 'SST_Notify';
    $hash->{AttrFn}      = 'SST_Attribute';
    #$hash->{ReadFn}     = 'SST_Read';
    #$hash->{parseParams} = 1;

    # ENTRYPOINT new device types (2/4)
    my @attrList = (
        'autocreate:0,1,2',
        'autoextend_setList:1,0',
        'brief_readings:1,0',
        'confirmation_delay',
        'device_id',
        'device_name',
        'device_type:CONNECTOR,refrigerator,freezer,TV,washer,dryer,vacuumCleaner,room_a_c',
        'disable:1,0',
        'discard_units:1,0',
        'get_timeout',
        'interval',
        'IODev',
        'readings_map',
        'setList',
        'setList_static',
        'set_timeout'
    );
    $hash->{AttrList} = join(" ", @attrList)." ".$readingFnAttributes;
}

#####################################
# DEFINITION
sub SST_Define($$) {
    my ($hash, $def) = @_;
    return "Cannot define device. Please install the following perl module(s) manually: $SST_missing_modules." if ($SST_missing_modules);

    my @aArguments = split('[ \t]+', $def);
    my $syntax     = "Syntax:\n\tdefine <name> SST <Samsung SmartThings Token>\nor\n\tdefine <name> SST <device type> IODev=<connector name>";
    return "Not enough arguments!\n$syntax" if $#aArguments < 2;

    # store name and token
    my $def_interval  = -1;
    my $tokenOrDevice = '';
    $hash->{name}     = $aArguments[0];
    $attr{$aArguments[0]}{device_type} = '';
    $attr{$aArguments[0]}{IODev}       = '';

    # ENTRYPOINT new device types (3/4)
    my $predefines = {
        'CONNECTOR' => {
            'icon' => 'samsung_smartthings',
        },
        'refrigerator' => {
            'icon' => 'samsung_sidebyside',
            'stateFormat' => 'cooler_temperature °C (cooler_contact)<br>\nfreezer_temperature °C (freezer_contact)',
        },
        'room_a_c' => {
            'icon' => 'samsung_ac',
            'stateFormat' => 'airConditionerMode',
            'setList_static' => 'fanOscillationMode:all,fixed,horizontal,vertical',
            'readings_map' => 'switch:on=an,off=aus',
        },
        'washer' => {
            'icon' => 'scene_washing_machine',
            'stateFormat' => 'machineState<br>washerJobState',
            'readings_map' => 'washerCycle:Table_00_Course_5B=Baumwolle,Table_00_Course_5C=Schnelle_Wäsche,Table_00_Course_63=Trommelreinigung,Table_00_Course_65=Wolle,Table_00_Course_67=Synthetik,Table_02_Course_1B=Baumwolle,Table_02_Course_1C=ECO_40-60,Table_02_Course_1D=SuperSpeed,Table_02_Course_1E=Schnelle_Wäsche,Table_02_Course_1F=Kaltwäsche_Intensiv,Table_02_Course_20=Hygiene-Dampf,Table_02_Course_21=Buntwäsche,Table_02_Course_22=Wolle,Table_02_Course_23=Outdoor,Table_02_Course_24=XXL-Wäsche,Table_02_Course_25=Pflegeleicht,Table_02_Course_26=Feinwäsche,Table_02_Course_27=Spülen+Schleudern,Table_02_Course_28=Abpumpen+Schleudern,Table_02_Course_29=Trommelreinigung+,Table_02_Course_2A=Jeans,Table_02_Course_2D=Super_Leise,Table_02_Course_2E=Baby_Care_Intensiv,Table_02_Course_2F=Sportkleidung,Table_02_Course_30=Bewölkter_Tag,Table_02_Course_32=Hemden,Table_02_Course_33=Handtücher',
            #'readings_map' => 'washerCycle:DUMMY=DUMMY',
            #'readings_map' => 'washerCycle:5B=Baumwolle,5C=Schnelle_Wäsche,63=Trommelreinigung,65=Wolle,67=Synthetik',
            #'readings_map' => 'washerCycle:1B=Baumwolle,1C=ECO_40-60,1D=SuperSpeed,1E=Schnelle_Wäsche,1F=Kaltwäsche_Intensiv,20=Hygiene-Dampf,21=Buntwäsche,22=Wolle,23=Outdoor,24=XXL-Wäsche,25=Pflegeleicht,26=Feinwäsche,27=Spülen+Schleudern,28=Abpumpen+Schleudern,29=Trommelreinigung+,2A=Jeans,2D=Super_Leise,2E=Baby_Care_Intensiv,2F=Sportkleidung,30=Bewölkter_Tag,32=Hemden,33=Handtücher',
        },
        'tv' => {
            'icon' => 'samsung_tv',
            'stateFormat' => 'switch<br>tvChannel',
        },
        'vacuumCleaner' => {
            'icon' => 'vacuum_top',
        }
    };

    # on more attributes - analyze and act correctly
    my $index = 2;
    while( $index <= $#aArguments ){
        if( $aArguments[$index] =~ m/^[0-9]+$/ ){
            # numeric value -> interval
            if( $def_interval == -1 ){
                $def_interval = $aArguments[$index];
            }else{
                fhem "delete $aArguments[0]";
                return "Interval given more than once!\n$syntax";
            }
            if( $aArguments[$index] >= 0 and $aArguments[$index] < 15 ){
                fhem "delete $aArguments[0]";
                return "Given interval of $aArguments[$index] is too low!\nSet to 0 for manual scan or choose value higher than 14.\n$syntax";
            }
        }elsif( $aArguments[$index] =~ m/^[0-9a-f-]{36}$/ ){
            # 32 digit hexadecimal value (plus 4 -) -> device id or Samsung SmartThings Token
            if( $tokenOrDevice eq '' ){
                $tokenOrDevice = $aArguments[$index];
            }else{
                fhem "delete $aArguments[0]";
                return "Device ID or token given more than once <$tokenOrDevice>/$aArguments[$index]!\n$syntax";
            }
        }elsif( $aArguments[$index] =~ m/^io[^= ]*=(.*)$/i ){
            # option IODevice
            if( $attr{$aArguments[0]}{IODev} eq '' ){
                $attr{$aArguments[0]}{IODev} = $1;
            }else{
                fhem "delete $aArguments[0]";
                return "IO device given more than once!\n$syntax";
            }
        }elsif( $aArguments[$index] =~ m/^[A-Za-z_]+$/ ){
            # one upper/lowercase word -> device type
            if( $attr{$aArguments[0]}{device_type} eq '' ){
                $attr{$aArguments[0]}{device_type} = $aArguments[$index];
            }else{
                fhem "delete $aArguments[0]";
                return "Device type given more than once!\n$syntax";
            }
        }else{
            fhem "delete $aArguments[0]";
            return "Unknown argument $index/$#aArguments: '$aArguments[$index]'!\n$syntax";
        }
        $index++;
    }

    # make sure we have a device type
    $attr{$aArguments[0]}{device_type} = 'CONNECTOR' if $attr{$aArguments[0]}{device_type} eq '';

    # if we're in a redefine, don't set any defaults
    if( not defined $hash->{TOKEN} and not defined $attr{$aArguments[0]}{device_id} ){
        # differ device types
        if( $attr{$aArguments[0]}{device_type} eq 'CONNECTOR' ){
        }else{
        }
    }
    # differ device types
    my $redefine = 1;
    if( $attr{$aArguments[0]}{device_type} eq 'CONNECTOR' ){
        # if we're in a redefine, don't set any defaults
        unless( defined $hash->{TOKEN} ){
            $hash->{TOKEN} = $tokenOrDevice;
            $def_interval = 86400 if $def_interval < 0;
            $attr{$aArguments[0]}{interval} = $def_interval;
            $redefine = 0;
        }
        delete $attr{$aArguments[0]}{IODev};
        delete $attr{$aArguments[0]}{setList};
    }else{
        # if we're in a redefine, don't set any defaults
        unless( defined $attr{$aArguments[0]}{device_id} ){
            $def_interval = 300 if $def_interval < 0;
            $attr{$aArguments[0]}{interval} = $def_interval;
            $attr{$aArguments[0]}{device_id} = $tokenOrDevice if $tokenOrDevice;
            $redefine = 0;
        }
    }
    unless( $redefine ){
        # set specific defaults
        foreach ( keys %{ $predefines->{ lc( $attr{$aArguments[0]}{device_type} ) } } ){
            $attr{$aArguments[0]}{$_} = $predefines->{ $attr{$aArguments[0]}{device_type} }->{$_};
        }
        $attr{$aArguments[0]}{icon} = 'unknown' unless defined $attr{$aArguments[0]}{icon};
    }

    Log3 $aArguments[0], 3, "SST ($aArguments[0]): define - $attr{$aArguments[0]}{device_type} defined as $aArguments[0]";

    # start timer for auto-rescan unless we're in config mode
    SST_ProcessTimer($hash) if $init_done;

    return undef;
}

#####################################
# ATTRIBUTES
sub SST_Attribute($$) {
    my ($type, $device, $attribute, @parameter) = @_;
    my $hash = $defs{$device};
    return undef unless $init_done;
    # TODO: auto change defaults when device_type changes

    Log3 $hash, 4, "SST ($device): attribute change - $attribute to $parameter[0]";
    if( $attribute eq 'interval' ){
        if( $parameter[0] == 0 ){
            # stop polling
            RemoveInternalTimer($hash);
        }elsif( not IsDisabled($device) ){
            # start/update polling
            SST_ProcessTimer($hash);
        }
    }elsif( $attribute eq 'disable' ){
        if( $parameter[0] == 1 ){
            # stop polling
            RemoveInternalTimer($hash);
        }else{
            # restart/update polling
            SST_ProcessTimer($hash);
        }
    }
    return undef;
}

#####################################
# NOTIFIES
sub SST_Notify($$) {
    my ($hash, $notifyhash) = @_;
    my $device    = $hash->{NAME};
    my $notifyer  = $notifyhash->{NAME}; # Device that created the events
    my $notifymsg = deviceEvents($notifyhash, 1);

    if( $notifyer eq 'global' ){
        if( grep(m/^INITIALIZED|REREADCFG$/, @{$notifymsg}) ){
            # after configuration/startup
            SST_ProcessTimer($hash) unless IsDisabled( $device );
        }elsif( grep(m/^RENAMED/, @{$notifymsg}) ){
            my ( $task, $oldname, $newname ) = split ' ', $notifymsg->[0];
            # renaming myself
            if( $newname eq $device ){
                my $msg = '';
                if( AttrVal($device, 'device_type', 'CONNECTOR') eq 'CONNECTOR' ){
                    # connector - update physical devices
                    foreach my $reading ( keys %{$hash->{READINGS}} ){
                        next unless $reading =~ /^device_/;
                        my $physnm = $hash->{READINGS}->{$reading}->{VAL};
                        if( $physnm ){
                            my $physdt = AttrVal( $physnm, 'device_type', 'unknown' );
                            my $physid = AttrVal( $physnm, 'device_id', 'unknown' );
                            fhem( "defmod $physnm SST $physdt $physid IO=$newname" );
                        }else{
                            Log3 $hash, 2, "SST ($device): notify - could not identify FHEM device name for reading $reading";
                            $msg .= "\nCould not identify FHEM device name for reading $reading!";
                        }
                    }
                    return $msg;
                }else{
                    # physical device - update connector
                    my $connector = AttrVal($device, 'IODev', undef);
                    my $device_id = AttrVal($device, 'device_id', undef);
                    fhem( "setReading $connector device_$device_id $newname" );
                }
            }
        }
    }
    return undef;
}

#####################################
# UNDEFINE/DELETE
sub SST_Undefine($$) {
    my ($hash, $arg) = @_;
    my $device = $hash->{NAME};
    RemoveInternalTimer($hash);

    if( AttrVal( $device, 'device_type', 'CONNECTOR' ) eq 'CONNECTOR' ){
        # TODO: delete all associated devices
        # remove client devices
        # foreach reading
        # delete client
        # done
    }else{
        # reset reading in CONNECTOR
        my $connector = AttrVal($device, 'IODev', undef);
        my $device_id = AttrVal($device, 'device_id', undef);
        fhem( "setReading $connector device_$device_id deleted" );
        Log3 $hash, 3, "SST ($device): delete - reset reading in connector $connector";
    }
    return undef;
}

#####################################
# GET COMMAND
sub SST_Get($@) {
    my ($hash, @aArguments) = @_;
    return '"get $hash->{name}" needs at least one argument' if int(@aArguments) < 2;
    my $device  = shift @aArguments;
    my $command = shift @aArguments;
    Log3 $hash, 5, "SST ($device): get command - received $command";

    # differ on specific get command
    if( $command eq 'device_list' ){
        return SST_getDeviceDetection($hash->{NAME} );
    }elsif( $command eq 'status' or $command eq 'x_options' ){
        return SST_getDeviceStatus( $hash->{NAME}, $command );
    }else{
        if( AttrVal( $device, 'device_type', 'CONNECTOR' ) eq 'CONNECTOR' ){
            return "Unknown argument $command, choose one of device_list:noArg";
        }else{
            return "Unknown argument $command, choose one of status:noArg x_options:noArg";
        }
    }
}

#####################################
# PROCESS TIMER
sub SST_ProcessTimer($) {
    my ($hash) = @_;
    my $device = $hash->{NAME};
    my $interval = AttrNum( $device, 'interval', 0 );
    my $disabled = AttrNum( $device, 'disable',  0 );
    my $nextrun  = gettimeofday() + $interval;

    if( $interval and not $disabled ){
        RemoveInternalTimer($hash);
        Log3 $hash, 5, "SST ($device): reschedule - running command first";
        if( AttrVal( $device, 'device_type', 'CONNECTOR' ) eq 'CONNECTOR' ){
            SST_getDeviceDetection($device);
        }else{
            SST_getDeviceStatus($device, 'status');
        }
        Log3 $hash, 4, "SST ($device): reschedule - next update in $interval seconds";
        InternalTimer( $nextrun, 'SST_ProcessTimer', $hash );
    }
    return undef;
}

#####################################
# SET COMMAND
sub SST_Set($@) {
    my ($hash, @aArguments) = @_;
    return '"set SST" needs at least one argument' if (int(@aArguments) < 2);

    # read arguments
    my $device      = shift @aArguments;
    my $reading     = shift @aArguments;
    my $device_type = AttrVal( $device, 'device_type', 'CONNECTOR' );
    my $connector   = AttrVal( $device, 'IODev', undef );
    my $read_delay  = AttrNum( $device, 'confirmation_delay', 3 );
    my $msg         = undef;
    my $token       = undef;
    my $data        = undef;
    my $command     = '';

    # we need this for FHEMWEB
    if( $reading eq '?' ){
        return "Unknown argument $reading, choose one of " if $device_type eq 'CONNECTOR';
        my $setlist = AttrVal( $device, 'setList', '' );
        return "Unknown argument $reading, choose one of $setlist";
    }

    # unless CONNECTOR, get token
    return 'connector device does not support set commands' if $device_type eq 'CONNECTOR';
    return "Could not identify IO Device for $device - please check configuration." unless $connector;
    $token = InternalVal( $connector, 'TOKEN', undef );
    return "Could not identify Samsung SmartThings token for $device - please check configuration." unless $token;

    # exit if reading is unknown
    return "Could not identify internal name for value $reading!" unless defined $hash->{'.R2CCC'}->{$reading};

    # split up communication path
    my ($component, $capability, $module) = split( '_', $hash->{'.R2CCC'}->{$reading} );
    Log3 $hash, 4, "SST ($device): set $component/$capability - $module/" . join( ',', @aArguments );

    # possibly translate 1st command prior cloud connect
    foreach ( split /\s+/, AttrVal( $device, 'readings_map', '' ) ){
        my ( $rm_reading, $rm_mapping ) = split /:/;
        next unless $rm_reading eq $reading;
        foreach( split /,/, $rm_mapping ){
            my ( $rm_value, $rm_display ) = split /=/;
            $aArguments[0] = $rm_value if "$aArguments[0]" eq "$rm_display";
        }
    }

    # try to auto-identify command name
    if( $module eq 'switch' ){
        # easy for switches...
        $command = shift @aArguments;
    }elsif( $capability eq 'thermostatCoolingSetpoint' ){
        # this does not follow the common rule
        $command = 'setCoolingSetpoint';
    }elsif( $module =~ m/^set/ ){
        # seems legit
        $command = $module;
    }else{
        # the common rule
        $command = 'set' . ucfirst($module);
    }

    # prepare data struct
    $data->{commands}->[0]->{component}  = $component;
    $data->{commands}->[0]->{capability} = $capability;
    $data->{commands}->[0]->{command}    = $command;
    $data->{commands}->[0]->{arguments}  = ();

    # handle/set command arguments
    for( my $i = 0 ; $i <= $#aArguments ; $i++ ){
        if( $aArguments[$i] =~ m/^[0-9]+$/ or $aArguments[$i] =~ m/^-\d+/ ){
            if( $capability =~ m/coolingSetpoint/i or $command =~ m/coolingSetpoint/i ){
                # if it looks like a number and we expect a number - send a number
                push @{ $data->{commands}->[0]->{arguments} }, int $aArguments[$i];

                # temperatures don't like a unit when being set - skip it
                if( $i < $#aArguments ){
                    $i++ if $aArguments[$i+1] =~ m/^[FC]$/i;
                }
            }
        }elsif( $aArguments[$i] =~ m/^On$|^Off$/ ){
            # and force lowercase On/Off command
            push @{ $data->{commands}->[0]->{arguments} }, lc $aArguments[$i];
        }else{
            # keep anything else as received
            push @{ $data->{commands}->[0]->{arguments} }, $aArguments[$i];
        }
    }

    my $jsoncmd = encode_utf8(encode_json($data));
    Log3 $hash, 5, "SST ($device): JSON STRUCT (device set $capability):\n" . $jsoncmd;

    # push command into cloud
    my $webpost  = HTTP::Request->new('POST', 
        'https://api.smartthings.com/v1/devices/' . AttrVal($device, 'device_id', undef) . '/commands',
        ['Authorization' => "Bearer: $token"],
        $jsoncmd
    );
    my $webagent = LWP::UserAgent->new( timeout => AttrNum($device, 'set_timeout', 15) );
    my $jsondata = $webagent->request($webpost);
    Log3 $hash, 5, "SST ($device): JSON STRUCT (device set $capability reply):\n" . $jsondata->content;

    # non-expected server reply
    if( not $jsondata->content ){
        Log3 $hash, 2, "SST ($device): set $component/$capability - sending failed";
        $hash->{STATE} = 'cloud connection error';
        return "Could not set $capability for Samsung SmartThings devices.\nPlease check your configuration.";
    }elsif( $jsondata->content =~ m/^read timeout/ ){
        Log3 $hash, 3, "SST ($device): set $component/$capability - probably failed: cloud query timed out";
        readingsSingleUpdate($hash, 'set_timeouts', AttrNum($device, 'set_timeouts', 0) + 1, 1);
        readingsSingleUpdate($hash, 'set_timeouts_row', AttrNum($device, 'set_timeouts_row', 0) + 1, 1);
        $hash->{STATE} = 'cloud timeout';

        # update readings - it could have been successful
        InternalTimer( gettimeofday() + $read_delay, 'SST_ProcessTimer', $hash );
        return "Updating $capability may have failed due to timeout." if AttrNum($device, 'verbose', 3) >= 4;
    }elsif( $jsondata->content !~ m/^\{"/ ){
        Log3 $hash, 2, "SST ($device): set $component/$capability - failed: cloud did not answer with JSON string:\n" . $jsondata->content;
        $hash->{STATE} = 'cloud return data error';
        return "Samsung SmartThings did not return valid JSON data string.\nPlease check log file for detailed information if this error persists.";
    }

    # reset timeout counter if neccessarry
    readingsSingleUpdate($hash, 'set_timeouts_row', 0, 1) if ReadingsNum($device, 'set_timeouts_row', 0) > 0;

    # on error
    my $jsonhash = decode_json($jsondata->content);
    if( defined $jsonhash->{error} ){
        Log3 $hash, 2, "SST ($device): set $component/$capability - failed: full JSON command and reply:\n$jsoncmd\n" . $jsondata->content;
        $msg = "Command has results:\n$jsoncmd\n" . $jsondata->content;
        $msg =~ s/,/,\n/g;
        return "Command failed:\n" . $jsonhash->{error}->{code} . ": " . $jsonhash->{error}->{message} . "\n$msg";
    }elsif( defined $jsonhash->{results} ){
        if( $jsonhash->{results}->[0]->{status} eq 'ACCEPTED' ){
            Log3 $hash, 4, "SST ($device): set $component/$capability - successfuly accepted";
            $msg = undef;
        }else{
            Log3 $hash, 3, "SST ($device): set $component/$capability - did not fail with response:\n" . $jsondata->content;
            $msg = "Command has results:\n$jsoncmd\n" . $jsondata->content;
        }
    }else{
        Log3 $hash, 3, "SST ($device): set $component/$capability - did neither fail nor was successful with response:\n" . $jsondata->content;
        $msg = "Command unambigious:\n$jsoncmd\n" . $jsondata->content;
    }

    # update readings
    InternalTimer( gettimeofday() + $read_delay, 'SST_ProcessTimer', $hash );
    return $msg;
}

#####################################
# device listing/creation
sub SST_getDeviceDetection($) {
    my ($device) = @_;
    my $hash     = $defs{$device};
    return 'device detection only works on connector device' if AttrVal($device, 'device_type', 'CONNECTOR') ne 'CONNECTOR';
    $hash->{STATE} = 'polling device list from cloud';

    # get list from cloud
    my $token    = $hash->{TOKEN};
    return "Could not identify Samsung SmartThings token for $device - please check configuration." unless $token;
    my $webget   = HTTP::Request->new('GET', 
        'https://api.smartthings.com/v1/devices/',
        ['Authorization' => "Bearer: $token"]
    );
    my $webagent = LWP::UserAgent->new( timeout => AttrNum($device, 'get_timeout', 10) );
    my $jsondata = $webagent->request($webget);

    if( not $jsondata->content ){
        Log3 $hash, 2, "SST ($device): get device_list - retrieval failed";
        $hash->{STATE} = 'cloud connection error';
        return "Could not obtain listing for Samsung SmartThings devices.\nPlease check your configuration.";
    }elsif( $jsondata->content =~ m/^read timeout/ ){
        Log3 $hash, 3, "SST ($device): get device_list - cloud query timed out";
        readingsSingleUpdate($hash, 'get_timeouts', AttrNum($device, 'get_timeouts', 0) + 1, 1);
        readingsSingleUpdate($hash, 'get_timeouts_row', AttrNum($device, 'get_timeouts_row', 0) + 1, 1);
        $hash->{STATE} = 'cloud timeout';
        return 'Retrieval of device listing timed out.';
    }elsif( $jsondata->content !~ m/^\{"/ ){
        Log3 $hash, 2, "SST ($device): get device_list - cloud did not answer with JSON string:\n" . $jsondata->content;
        $hash->{STATE} = 'cloud return data error';
        return "Samsung SmartThings cloud did not return valid JSON data string.\nPlease check log file for detailed information if this error repeats.";
    }

    # reset timeout counter
    readingsSingleUpdate($hash, 'get_timeouts_row', 0, 1) if AttrNum($device, 'get_timeouts_row', 0) > 0;

    my $items    = decode_json($jsondata->content);
    my $count    = scalar @{ $items->{items}};
    my $msg      = '';
    if( AttrNum($device, 'verbose', '0') >= 5 ){
        $msg .= "\n------ send below text to developer ------\n\n";
        $msg .= Dumper($items);
        #$msg .= $jsondata->content;
        $msg =~ s/$token/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX/g;
        $msg =~ s/[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/g;
        $msg .= "\n------ send above text to developer ------\n\n";
    }
    $msg .= 'Device-ID - Name';
    $msg .= ' - Autocreation Status' if AttrNum($device, 'autocreate', '0') > 0;
    $msg .= "\n\n";
    my $xxx = '';
    for(my $i = 0; $i < $count; $i++) {
        my $deviceId = $items->{items}[$i]->{deviceId};
        my $name = $items->{items}[$i]->{name};
        $msg .= "$deviceId - $name";

        if( AttrNum($device, 'verbose', '0') == 4 ){
            my $compcount = scalar @{ $items->{items}[$i]->{components} };
            for(my $j = 0; $j < $compcount; $j++) {
                $xxx .= $items->{items}[$i]->{components}[$j]->{id} . ':';
                my $capacount = scalar @{ $items->{items}[$i]->{components}[$j]->{capabilities} };
                for(my $k = 0; $k < $capacount; $k++) {
                    $xxx .= "\n - " . $items->{items}[$i]->{components}[$j]->{capabilities}[$k]->{id};
                }
                $xxx .= "\n";
            }
        }

        if( ReadingsVal($device, "device_$deviceId", '') eq '' ){
            # create new reading if missing
            if( readingsSingleUpdate($hash, "device_$deviceId", 'new', 1) ){
                Log3 $hash, 3, "SST ($device): get device_list - added new client device '$deviceId'";
            }else{
                Log3 $hash, 2, "SST ($device): get device_list - failed adding new client device '$deviceId'";
                next;
            }
        }else{
            Log3 $hash, 4, "SST ($device): get device_list - skipping known device '$deviceId'";
        }

        if( AttrNum($device, 'autocreate', '0') > 0 ){
            if( ReadingsVal($device, "device_$deviceId", '') eq 'new' or AttrNum($device, 'autocreate', '0') == 2 ){
                # build (temporary/automatic) device name
                my $tmpname = $items->{items}[$i]->{deviceId};
                $tmpname =~ s/.*-/SST_/;
                $tmpname =~ s/\s//;
                if( $tmpname eq 'SST_000000000000' ){
                    $tmpname = $items->{items}[$i]->{deviceId};
                    $tmpname =~ s/[\s-]//g;
                    $tmpname =~ s/^(.{12}).*$/SST_$1/;
                }

                # ENTRYPOINT new device types (1/4)
                # try to determine the device type
                my $subdevicetype = 'unknown';
                if( $items->{items}[$i]->{name} =~ m/^\[(.*)\]/ ){
                    $subdevicetype = $1;
                }elsif( $items->{items}[$i]->{deviceTypeName} =~ m/ OCF (.*)$/ ){
                    $subdevicetype = $1;
                }elsif( $items->{items}[$i]->{deviceTypeName} =~ m/TV/ ){
                    $subdevicetype = 'TV';
                }else{
                    $msg .= 'cannot determine device type from name (' . $items->{items}[$i]->{name} . ') or deviceTypeName (' . $items->{items}[$i]->{deviceTypeName} . ').';
                    Log3 $hash, 2, "SST ($device): get device_list - cannot determine device type from name (" . $items->{items}[$i]->{name} . ') or deviceTypeName (' . $items->{items}[$i]->{deviceTypeName} . ').';
                }
                $subdevicetype =~ s/[\s\/]/_/g;

                # create new device
                Log3 $hash, 3, "SST ($device): get device_list - automatically adding device $tmpname as $subdevicetype";
                fhem( "define $tmpname SST $subdevicetype IO=$device" );
                if( AttrVal($tmpname, 'device_type', undef) ){
                    $msg .= " - newly created as $tmpname";
                    fhem "attr $tmpname device_id " . $items->{items}[$i]->{deviceId};
                    fhem "attr $tmpname device_name " . $items->{items}[$i]->{name};
                    unless( readingsSingleUpdate($hash, "device_$deviceId", "$tmpname", 1) ){
                        Log3 $hash, 2, "SST ($device): get device_list - reading update for $deviceId failed - disabling autocreate";
                        fhem( "attr $device autocreate 0" );
                    }
                }else{
                    $msg .= " - creation failed with: '$subdevicetype, 60, " . $items->{items}[$i]->{deviceId} . " IO=$device'";
                }
            }else{
                $msg .= ' - already known: no creation';
            }
        }
        $msg .= "\n\n";
        $msg .= $xxx;
    }
    # reset autocreate to 1 (create new devices only)
    $attr{$device}{autocreate} = 1 if AttrNum( $device, 'autocreate', 0) == 2;
    readingsSingleUpdate($hash, 'lastrun', FmtDateTime(time()), 1);
    $hash->{STATE} = 'connection idle';
    return $msg;
}

#####################################
# device status/details or options
sub SST_getDeviceStatus($$) {
    my ($device, $modus) = @_;
    my $hash             = $defs{$device};
    my $device_type      = AttrVal($device, 'device_type', 'CONNECTOR');
    my $nounits          = AttrNum($device, 'discard_units', 1);
    my $token            = undef;
    return "Cannot get $modus for the CONNECTOR device." if $device_type eq 'CONNECTOR';
    my $connector = AttrVal($device, 'IODev', undef);
    return "Could not identify IO Device for $device - please check configuration." unless $connector;
    $token = InternalVal( $connector, 'TOKEN', undef );
    return "Could not identify Samsung SmartThings token for $device - please check configuration." unless $token;

    # poll cloud for all status objects (all components)
    Log3 $hash, 4, "SST ($device): get $modus - query cloud service";
    my $webget   = HTTP::Request->new('GET', 
        'https://api.smartthings.com/v1/devices/' . AttrVal($device, 'device_id', undef) . '/status',
        ['Authorization' => "Bearer: $token"]
    );
    my $webagent = LWP::UserAgent->new( timeout => AttrNum($device, 'get_timeout', 10) );
    my $jsondata = $webagent->request($webget);
    if( not $jsondata->content ){
        Log3 $hash, 2, "SST ($device): get $modus - failed (empty string)";
        $hash->{STATE} = 'cloud connection error';
        return "Could not obtain $modus for Samsung SmartThings Device $device.\nPlease check your configuration.";
    }elsif( $jsondata->content =~ m/^read timeout/ ){
        Log3 $hash, 3, "SST ($device): get $modus - cloud query timed out";
        readingsSingleUpdate($hash, 'get_timeouts', AttrNum($device, 'get_timeouts', 0) + 1, 1);
        readingsSingleUpdate($hash, 'get_timeouts_row', AttrNum($device, 'get_timeouts_row', 0) + 1, 1);
        $hash->{STATE} = 'cloud timeout';
        return "Data retrieval timed out.";
    }elsif( $jsondata->content !~ m/^\{"/ ){
        Log3 $hash, 2, "SST ($device): get $modus - cloud did not answer with JSON string:\n" . $jsondata->content;
        $hash->{STATE} = 'cloud return data error';
        return "Samsung SmartThings cloud did not return valid JSON data string.\nPlease check log file for detailed information if this error repeats.";
    }

    # reset timeout counter
    readingsSingleUpdate($hash, 'get_timeouts_row', 0, 1) if AttrNum($device, 'get_timeouts_row', 0) > 0;

    # TODO: possibly read in some manual disabled capabilities from attribute or reading
    my $jsonhash       = decode_json($jsondata->content);
    my @setListHints   = ();
    my %ccc2cmd        = ();
    my @disabled       = ();
    my %readings       = ();
    my $brief_readings = AttrNum($device, 'brief_readings', 1);
    my $readings_v2d   = undef;

    # fill set command mapping
    foreach ( split /\s+/, AttrVal( $device, 'readings_map', '' ) ){
        my ( $rm_reading, $rm_mapping ) = split /:/;
        foreach( split /,/, $rm_mapping ){
            my ( $rm_value, $rm_display ) = split /=/;
            $readings_v2d->{$rm_reading}->{$rm_value} = $rm_display;
        }
    }

    # ENTRYPOINT new options
    my %setpointrange = ();
    my %option2reading = {
        'custom.airConditionerOptionalMode' => 'acOptionalMode',
        #'custom.supportedOptions' => 'washerCycle',
        'custom.washerRinseCycles' => 'washerRinseCycles',
        'custom.washerSpinLevel' => 'washerSpinLevel',
        'custom.washerWaterTemperature' => 'washerWaterTemperature',
    };

    # parse JSON struct
    Log3 $hash, 5, "SST ($device): get $modus - received JSON data";
    foreach my $baselevel ( keys %{ $jsonhash } ){
        unless( $baselevel eq 'components' ){
            Log3 $hash, 4, "SST ($device): get $modus - unexpected branch: $baselevel";
            next;
        }
        foreach my $component ( keys %{ $jsonhash->{$baselevel} } ){
            foreach my $capability ( keys %{ $jsonhash->{$baselevel}->{$component} } ){
                #Log3 $hash, 5, "SST ($device): get $modus - parsing component: $component";

                if( $capability eq 'execute' ){
                    foreach my $collection ( keys %{ $jsonhash->{$baselevel}->{$component}->{execute}->{data}->{value}->{payload} } ){
                        if( $collection =~ m/options$/ ){
                            foreach my $set ( @{ $jsonhash->{$baselevel}->{$component}->{execute}->{data}->{value}->{payload}->{$collection} } ){
                                my ( $exkey, $exval ) = split /_/, $set;
                                my $reading = makeReadingName( $component . '_execute-payload_option-' . $exkey );
                                $readings{$reading} = $exval;
                            }
                        }
                    }
                    # we currently don't want readings for commands
                    next;
                }elsif( $capability =~ m/^custom.disabledC/ ){ # custom.disabledCapabilities / custom.disabledComponents
                    my $sub = $capability;
                    $sub =~ s/^custom\.//;
                    if( defined $jsonhash->{$baselevel}->{$component}->{$capability}->{$sub}->{value} ){
                        # store it for later
                        foreach ( @{ $jsonhash->{$baselevel}->{$component}->{$capability}->{$sub}->{value} } ){
                            push( @disabled, $component . '_' . $_ );
                        }
                    }
                    next;
                }

                if( ref $jsonhash->{$baselevel}->{$component}->{$capability} eq 'HASH' ){
                    foreach my $module ( keys %{ $jsonhash->{$baselevel}->{$component}->{$capability} } ){
                        #Log3 $hash, 5, "SST ($device): get $modus - parsing module: $module in $capability in $component in $baselevel";
                        if( ref $jsonhash->{$baselevel}->{$component}->{$capability}->{$module} eq 'HASH' ){
                            if( defined $jsonhash->{$baselevel}->{$component}->{$capability}->{$module}->{value} ){
                                if( $component eq 'main' and $capability eq 'ocf' ){
                                    # let's limit the ocf readings
                                    next unless $module eq 'n' or $module eq 'mnmn' or $module eq 'mnmo' or $module eq 'vid';
                                }
                                my $reading = makeReadingName( $component . '_' . $capability . '_' . $module );
                                my $thisvalue = '';

                                # manage arrays - most likely options (ARRAYs)
                                if( ref $jsonhash->{$baselevel}->{$component}->{$capability}->{$module}->{value} eq 'ARRAY' ){
                                    # this might always indicate value options... let's assume that for the time being
                                    push @setListHints, $component . '_' . $capability . ':' . join( ',', @{ $jsonhash->{$baselevel}->{$component}->{$capability}->{$module}->{value} } );
                                    # heed mapping
                                    if( defined $option2reading{$module} ){
                                        $reading = makeReadingName( $component . '_' . $capability . '_' . $option2reading{$module} );
                                    }else{
                                        # adapt reading name hope this will always work...
                                        $reading = makeReadingName( $component . '_' . $capability . '_' . $capability );
                                    }
                                    $ccc2cmd{$reading} = join( ',', @{ $jsonhash->{$baselevel}->{$component}->{$capability}->{$module}->{value} } );
                                    next;
                                }elsif( ref $jsonhash->{$baselevel}->{$component}->{$capability}->{$module}->{value} eq 'HASH' ){
                                    # multiple values (HASHes)
                                    foreach my $subval ( keys %{ $jsonhash->{$baselevel}->{$component}->{$capability}->{$module}->{value} } ){
                                        $thisvalue = $jsonhash->{$baselevel}->{$component}->{$capability}->{$module}->{value}->{$subval};

                                        # recalculate timestamps
                                        $thisvalue = FmtDateTime( fhemTimeGm( $6, $5, $4, $3, $2 - 1, $1 - 1900 ) )
                                            if $thisvalue =~ m/^([0-9]{4})-([0-9]{2})-([0-9]{2})T([012][0-9]):([0-5][0-9]):([0-5][0-9])[\.0-9]*Z/;

                                        # remember reading
                                        my $subreading = makeReadingName( $reading . '-' . $subval );
                                        $readings{$subreading} = $thisvalue;
                                    }
                                }else{
                                    $thisvalue = $jsonhash->{$baselevel}->{$component}->{$capability}->{$module}->{value};

                                    # recalculate timestamps
                                    $thisvalue = FmtDateTime( fhemTimeGm( $6, $5, $4, $3, $2 - 1, $1 - 1900 ) )
                                        if $thisvalue =~ m/^([0-9]{4})-([0-9]{2})-([0-9]{2})T([012][0-9]):([0-5][0-9]):([0-5][0-9])[\.0-9]*Z/;

                                    # save min and max limitations
                                    if( $module eq 'minimumSetpoint' ){
                                        $setpointrange{min} = $thisvalue;
                                        next;
                                    }elsif( $module eq 'maximumSetpoint' ){
                                        $setpointrange{max} = $thisvalue;
                                        next;
                                    }
                                    $setpointrange{cnt}++ if $module =~ m/Setpoint$/;

                                    # remember reading
                                    $readings{$reading} = $thisvalue;
                                    $readings{$reading} .= ' ' . $jsonhash->{$baselevel}->{$component}->{$capability}->{$module}->{unit}
                                        if( exists $jsonhash->{$baselevel}->{$component}->{$capability}->{$module}->{unit} and not $nounits );
                                }
                                next;
                            }

                            # delve into next level, where there is no value... :/
                            foreach my $attribute ( keys %{ $jsonhash->{$baselevel}->{$component}->{$capability}->{$module} } ){
                                next if $attribute eq 'timestamp'; # who cares about timestamps ...
                                next unless defined $jsonhash->{$baselevel}->{$component}->{$capability}->{$module}->{$attribute}; # ... or empty elements ...
                                next if $attribute eq 'unit' and not defined $jsonhash->{$baselevel}->{$component}->{$capability}->{$module}->{value}; # ... empty element's units
                                Log3 $hash, 3, "SST ($device): get $modus - unexpected reading at attribute level: $baselevel/$component/$capability/$module/$attribute of type " . ref( $jsonhash->{$baselevel}->{$component}->{$capability}->{$module}->{$attribute} );
                                # TODO: propably extend interpretation if someone gets even more info
                            } # foreach attribute
                        }else{
                            Log3 $hash, 3, "SST ($device): get $modus - unexpected non-hash reading at module level: $baselevel/$component/$capability/$module of type  " . ref( $jsonhash->{$baselevel}->{$component}->{$capability}->{$module} );
                        }
                    } # foreach module
                }else{
                    Log3 $hash, 3, "SST ($device): get $modus - unexpected non-hash reading at capability level: $baselevel/$component/$capability of type " . ref( $jsonhash->{$baselevel}->{$component}->{$capability} );
                }
            } # foreach capability
        } # foreach component
    } # foreach baselevel
    Log3 $hash, 5, "SST ($device): get $modus - identified disabled components:\n" . Dumper( [ @disabled ] );
    Log3 $hash, 5, "SST ($device): get $modus - identified readings:\n" . Dumper( { %readings } );
    Log3 $hash, 5, "SST ($device): get $modus - identified setList options:\n" . Dumper( [ @setListHints ] );

    # create/update all readings
    if( $modus eq 'status' ){
        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, 'setList_hint', join( "\n", sort @setListHints ), 1 ) if $#setListHints >= 0;
        EACHREADING: foreach my $key ( keys %readings ){
            my $reading = $key;

            # skip disabled capabilities
            foreach (@disabled){
                my $regex = '^' . $_ . '_';
                next EACHREADING if $key =~ m/$regex/;
            }

            # abbreviate reading name
            if( $brief_readings ){
                $reading =~ s/_[^_]+_/_/; # remove middle part (capability)
                $reading =~ s/^main_//i;  # remove main component
            }

            # possibly rewrite value from readings_map
            $readings{$key} = $readings_v2d->{$reading}->{$readings{$key}} if defined $readings_v2d->{$reading}->{$readings{$key}};

            # create reading
            readingsBulkUpdate( $hash, $reading, $readings{$key}, 1 );
        }
        readingsEndUpdate($hash, 1);
    }

    # store reading name mapping
    if( $modus ne 'status' or not defined $hash->{'.R2CCC'} ){
        # filling setList
        my %rdn2ccc=();
        my $setList = '';
        EACHREADING: foreach my $key ( sort keys %readings ){
            my $reading = $key;
            foreach (@disabled){
                my $regex = '^' . $_ . '_';
                next EACHREADING if $key =~ m/$regex/;
            }
            if( $brief_readings ){
                $reading =~ s/_[^_]+_/_/; # remove middle part (capability)
                $reading =~ s/^main_//i;  # remove main component
            }
            $rdn2ccc{$reading} = $key;
            # ENTRYPOINT new set options
            if( defined $ccc2cmd{$key} ){
                $setList .= " $reading:$ccc2cmd{$key}"; 
            }elsif( $key =~ m/_switch$/ ){
                $setList .= " $reading:on,off"; 
            }elsif( $key =~ m/^main_refrigeration_rapid/ ){
                $setList .= " $reading:On,Off"; # weirdly this is upper case on get, but lower case on set...
            }elsif( $key =~ m/Setpoint$/ ){
                $setList .= " $reading"; 
                if( defined( $setpointrange{min} ) and defined( $setpointrange{max} ) and $setpointrange{cnt} == 1 ){
                    $setList .= ':' . join ',', $setpointrange{min} .. $setpointrange{max};
                }elsif( $device_type eq 'refrigerator' ){
                    if( $key =~ m/^cooler_/ ){
                        $setList .= ':' . join ',', 1 .. 7;
                    }elsif( $key =~ m/^freezer_/ ){
                        $setList .= ':' . join ',', -23 .. -15;
                    }
                }
            }
        }
        $hash->{'.R2CCC'} = { %rdn2ccc };
        if( $modus eq 'x_options' ){
            my @newSetList = ();
            $setList .= ' ' . AttrVal( $device, 'setList_static', '' );
            $setList =~ s/^ //;
            $setList =~ s/ $//;
            foreach ( split / /, $setList ){
                my ( $sl_reading, $sl_mapping ) = split /:/, $_;
                if( defined $readings_v2d->{$sl_reading} ){
                    my $newSet = "$sl_reading";
                    foreach my $sl_value ( split /,/, $sl_mapping ){
                        $newSet .= ',';
                        if( defined $readings_v2d->{$sl_reading}->{$sl_value} ){
                            $newSet .= $readings_v2d->{$sl_reading}->{$sl_value};
                        }else{
                            $newSet .= $sl_value;
                        }
                    }
                    $newSet =~ s/,/:/;
                    push @newSetList, $newSet;
                }else{
                    push @newSetList, $_;
                }
            }
            $setList = join ' ', @newSetList;
            $attr{$device}{setList} = $setList;
        }
        Log3 $hash, 5, "SST ($device): get $modus - identified readings to c3 path mappings:\n" . Dumper( $hash->{'.R2CCC'} );
        return undef;
    }

    # TODO: possible deletion candidate
    # update setList if desired
    if( AttrNum($device, 'autoextend_setList', 0) > 0 ){
        # TODO: update/compare complete entry (with enum)
        my $setList_old = AttrVal( $device, 'setList', '' );
        my @setList_new = split ' ', AttrVal( $device, 'setList', '' );
        my $updated = 0;
        $setList_old =~ s/:[^ ]* / /g;
        $setList_old = " $setList_old ";
        foreach my $full_hint (@setListHints){
            my $capability = $full_hint;
            $capability =~ s/:.*//g;
            next if $setList_old =~ m/ $capability /;
            push @setList_new, $full_hint;
            $updated++;
        }
        if( $updated ){
            $attr{$device}{setList} = join ' ', @setList_new;
            Log3 $hash, 4, "SST ($device): get $modus - extended setList by $updated entries";
        }
    }

    return Dumper($jsonhash) if AttrNum($device, 'verbose', 0) >= 5;
    return undef;
}

1;

#####################################
# MANUAL
# TODO: complete it ;)
=pod
=item device
=item summary    Integration of Samsung SmartThings devices
=item summary_DE Einbindung von Samsung SmartThings Ger&auml;ten
=begin html

<br>
<a name="SST"></a>
<a name="48_SST.pm"></a>
<h3>SST - Samsung SmartThings Connector</h3>
<ul>
  <b>Please Note that this Module is currently in an early beta status. Not
  everything already works as described!</b><br>
  SST is a generic integration of Samsung SmartThings and its devices. On one
  hand it can be used to identify all SmartThings devices from the cloud and
  create its pendents in FHEM. The more daring users may also create the FHEM
  devices by themselves, though.<br>
  These FHEM devices may be renamed freely and should support most functions
  that the devices support in the Samsung SmartThings app.<br>
  <br>

  <a name="SSTdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SST &lt;SmartThings token&gt;</code><br>
    or<br>
    <code>define &lt;name&gt; SST &lt;device type&gt; IODev=&lt;connector
    device&gt;</code><br>
    <br>
    You need to give the <i>SmartThings token</i> which must be generated on <a 
    href="https://account.smartthings.com/tokens" 
    target='_blank'>https://account.smartthings.com/tokens</a> with at least
    the following permission:<ul>
    <li>Devices -> List all devices</li>
    <li>Devices -> See all devices</li>
    <li>Devices -> Control all devices</li>
    <li>Device Profiles -> See all device profiles</li>
    </ul>The creation of the real devices also requires the <i>device type</i>
    which is usually identified and created as a reading by the device_list
    command.<br>
    The connector needs to be given as the IODev, unless for the connector
    itself.<br>
  </ul><br>

  <a name="SSTset"></a>
  <b>Set</b>
  <ul>
    See the setList attribute documentation below.<br>
  </ul><br>

  <a name="SSTget"></a>
  <b>Get</b>
  <ul>

    <a name="list_devices"></a>
    <li>list_devices<br>
    This is only available for the connector device and will start the device
    detection. This refreshes the list of available SmartThings devices in the
    readings.<br>
    If <i>autocreate</i> (cf. below) is not set to 0, the FHEM devices will be
    created.<br></li>

    <a name="status"></a>
    <li>status<br>
    This is not available for the connector device and will refresh the list
    of available/useful SmartThings capabilities in the readings. The readings
    may differ greatly between different types of devices.<br></li>

    <a name="x_options"></a>
    <li>x_options<br>
    This is not available for the connector device and will overwrite the
    setList attribute with the corresponding information taken from the
    device's cloud response.<br>
    In order to display the changes, the FHEMWEB page needs to be reloaded.<br>
    </li>

  </ul><br>

  <a name="SSTattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="autocreate"></a>
    <li>autocreate {0|1|2}<br>
    Only valid for connector device. Defaults to <b>0</b> (off).<br>
    If set to <b>0</b> no individual devices will be created on device
    detection.<br>
    If set to <b>1</b> only uncreated devices will be created on device
    detection.<br>
    If set to <b>2</b> all devices will be recreated (this may produce errors
    due to previously undeleted devices) on device detection. After the
    detection/creation the value for <b>autocreate</b> is automatically reset
    to <b>1</b>.<br></li>

    <a name="autoextend_setList"></a>
    <li>autoextend_setList {0|1}<br>
    Not valid for connector device. Defaults to <b>0</b> (off).<br>
    If set to <b>1</b> all setting options identified during a status update
    that are not yet defined in setList will be written into the setList
    attribute.<br></li>

    <a name="brief_readings"></a>
    <li>brief_readings<br>
    Not valid for connector device. Defaults to <b>1</b> (on).<br>
    If set to <b>1</b> the cloud reading names will be abbreviated resulting in
    far more readable reading names.<br>
    If set to <b>0</b> these names will remain as received. Only this way
    unique names can be guaranteed. Use this if you think you miss some
    readings.<br></li>

    <a name="confirmation_delay"></a>
    <li>confirmation_delay<br>
    Not valid for connector device. Defaults to <b>3</b>.<br>
    Time in seconds to wait after setting values before checking the device
    status.<br></li>

    <a name="device_id"></a>
    <li>device_id<br>
    Not valid for connector device.<br>
    This is the 32 digits hexadecimal Samsung internal device ID token. To
    obtain it run the device detection and take it from the readings.<br>
    This attribute is automatically filled on device generation and usually
    does not require your attention.<br></li>

    <a name="device_name"></a>
    <li>device_name<br>
    Not valid for connector device.<br>
    This is the Samsung internal device name.<br>
    This attribute is automatically filled on device generation and usually
    does not require your attention.<br></li>

    <a name="device_type"></a>
    <li>device_type
    {CONNECTOR|refrigerator|freezer|washer|dryer|TV|vacuumCleaner}<br>
    Defaults to <b>CONNECTOR</b>.<br>
    This specifies the physical device type of this FHEM device.<br>
    A 'special' device type is <b>CONNECTOR</b> which is the instance for
    device detection and creation.<br>
    Each different device type has a different set of capabilities that will
    result in the different readings and options for the setList.
    This attribute is automatically filled on device generation and usually
    does not require your attention.<br></li>

    <a name="disable"></a>
    <li>disable {0|1}<br>
    Defaults to 0 (off).<br>
    A value of <b>1</b> disables auto-polling of device_list or status.</li>

    <a name="discard_units"></a>
    <li>discard_units {0|1}<br>
    Not valid for connector device. Defaults to <b>1</b> (off).<br>
    If set to <b>0</b> all readings (aka Samsung capabilities) will be stored
    including the transmitted units. This is not the default behaviour of FHEM.
    Thus you should only set this to <b>0</b> for debugging reasons.<br></li>

    <a name="get_timeout"></a>
    <li>get_timeout<br>
    Defaults to 10 seconds.
    This is the timeout for cloud get requests in seconds. If your get_timeouts
    reading gets excessive, increase this value.<br>
    Values too high might freeze FHEM on bad internet connections.<br></li>

    <a name="interval"></a>
    <li>interval<br>
    Defaults to <b>86400</b> (1 day) for the connector.<br>
    Defaults to <b>300</b> (5 minutes) for the physical devices.<br>
    This is the reload interval in seconds.<br></li>

    <a name="IODev"></a>
    <li>IODev<br>
    Not valid for connector device.<br>
    This is usually set on define and will allow you to identify connected
    devices from the connector device. It is also used for delting all pysical
    devices when deleting the connector device.<br>
    This attribute is automatically filled on device generation and usually
    does not require your attention.<br></li>

    <a name="readings_map"></a>
    <li>readings_map<br>
    Not valid for connector device.<br>
    With this list of set commands and aliases the displayed names for the
    readings and the set commands can be translated into something useful.<br>
    The format is:<br>
    <code>Reading:Value=Display[,Value=Display]</code><br></li>

    <a name="setList"></a>
    <li>setList<br>
    Not valid for connector device.<br>
    This is the list of set commands available for your device (type).<br>
    If autoextend_setList is set, this list may grow on status updates.<br></li>

    <a name="setList_static"></a>
    <li>setList_static<br>
    Not valid for connector device.<br>
    This is the list of set commands to be kept for your device (type) even on
    running x_options.<br>
    Any predefines by SST will be initially stored in this attribute.<br></li>

    <a name="set_timeout"></a>
    <li>set_timeout<br>
    Defaults to 15 seconds.
    This is the timeout for cloud set requests in seconds. If your set_timeouts
    reading gets excessive, increase this value.<br>
    Values too high might freeze FHEM on bad internet connections.<br></li>

  </ul><br>

  <a name="SSTreadings"></a>
  <b>Readings</b>
  <ul>

    <a name="devices"></a>
    <li>device_.*<br>
    These readings are created for the CONNECTOR for each client device
    identified from the Samsung SmartThings cloud service.<br></li>

    <a name="lastrun"></a>
    <li>lastrun<br>
    This reading is set for the CONNECTOR each time it successfully retrieves
    information from the Samsung SmartThings cloud service.<br></li>

    <a name="timeount_counter"></a>
    <li>timeount_counter<br>
    This reading shows how often the retieval of information from the Samsung
    SmartThings cloud service fails and when it did fail last.<br></li>

    <a name="other"></a>
    <li>other readings<br>
    All other readings for physical devices represent one, as Samsung calls
    them, capability. These capabilities vary greatly from device type to
    device type, so we cannot explain them here.<br></li>

  </ul><br>

</ul><br>

=end html

=begin html_DE

<br>
<a name="SST"></a>
<a name="48_SST.pm"></a>
<h3>SST - Samsung SmartThings Connector</h3>
<ul>
  Bitte beachten Sie, da&szlig; sich dieses Modul in einem fr&uuml;hen
  Beta-Stadium befindet. Noch nicht alles funktioniert wie beschrieben!<br>
  SST ist eine generische Modul zur Einbindung von Samsung SmartThings und den
  dort eingebundenen Ger&auml;ten. Hiermit k&ouml;nnen alle SmartThings
  Ger&auml;te aus der Cloud eingelesen werden, und ihre FHEM Pendents angelegt
  werden. Die erzeugten Ger&auml;te k&ouml;nnen dann in FHEM angezeigt und
  gesteuert werden.<br>
  <br>

  <a name="SSTdefine"></a>
  <b>Define</b>
  <ul>
    <li><b>Connector</b>:<br>
    <code>define &lt;name&gt; SST &lt;SmartThings token&gt;</code><br>
    <br>
    Zur Anlage des Connectors ist das <b>SmartThings token</b> n&ouml;tig,
    welches zun&auml;chst unter <a
    href="https://account.smartthings.com/tokens" target='_blank'
    >https://account.smartthings.com/tokens</a> erstellt werden mu&szlig;.
    Dieses Modul ben&ouml;tigt ein Token mit mindestens folgenden Rechten:<ul>
    <li>Devices -> List all devices</li>
    <li>Devices -> See all devices</li>
    <li>Devices -> Control all devices</li>
    <li>Device Profiles -> See all device profiles</li>
    </ul><br></li>

    <li><b>Phyische Ger&auml;te</b>:<br>
    <code>define &lt;name&gt; SST &lt;device type&gt; IODev=&lt;connector
    device&gt;</code><br>
    <br>
    <b>Sinnvollerweise &uuml;berl&auml;&szlig;t man diese Erstellung dem
    Connector.</b><br>
    Die Erstellung der FHEM Ger&auml;te f&uuml;r die physischen Ger&auml;te
    bedarf nur der Angabe des <b>device type</b>, &uuml;ber den die z.B. die
    m&ouml;glichen set Befehle vordefiniert werden, sowie des <b>IODev</b>,
    welches auf den Connector verweisen mu&szlig;.<br></li>
  </ul><br>

  <a name="SSTset"></a>
  <b>Set</b>
  <ul>
    See the setList attribute documentation below.<br>
  </ul><br>

  <a name="SSTget"></a>
  <b>Get</b>
  <ul>

    <a name="list_devices"></a>
    <li>list_devices<br>
    Diese Funktion steht nur beim Connector zur Verf&uuml;gung.<br>
    Hier&uuml;ber wird der Ger&auml;tescan gestartet, der dann s&auml;mtliche
    gefundnen SmartThings Ger&auml;te in Readings schreibt.<br>
    Wenn <i>autocreate</i> (s.u.) gesetzt ist, werden die entsprechenden FHEM
    Ger&auml;te angelegt.<br></li>

    <a name="status"></a>
    <li>status<br>
    Diese Funktion steht beim Connector nicht zur Verf&uuml;gung.<br>
    Hier&uuml;ber wird der Ger&auml;testatus &uuml;ber die Cloud abgefragt und
    in Readings geschrieben. Die verf&uuml;gbaren Readings unterscheiden sich
    stark zwischen verschiedenen Ger&auml;tetypen.<br></li>

    <a name="x_options"></a>
    <li>x_options<br>
    Diese Funktion steht beim Connector nicht zur Verf&uuml;gung.<br>
    Hier&uuml;ber wird eine Liste m&ouml;glicher Kommandos aus dem
    Ger&auml;testatus der Cloud erzeugt und in dem Attribut setList
    gespeichert.<br>
    Um die &auml;nderungen anzuzeigen, mu&szlig; die Seite in FHEMWEB neu
    geladen werden.<br></li>

  </ul><br>

  <a name="SSTattr"></a>
  <b>Attributes</b>
  <ul>

    <a name="autocreate"></a>
    <li>autocreate {0|1|2}<br>
    Nur f&uuml;r den Connector relevant. Default ist <b>0</b> (aus).<br>
    Bei einem Wert von <b>0</b> werden keine Ger&auml;te durch den
    Ger&auml;tescan angelegt.<br>
    Bei einem Wert von <b>1</b> werden nur neue, noch nicht angelegte
    Ger&auml;te durch den Ger&auml;tescan angelegt.<br>
    Bei einem Wert von <b>2</b> werden alle gefundenen Ger&auml;te durch den
    Ger&auml;tescan angelegt. Hierbei kann es zu Fehlermeldungen wegen zuvor
    nicht entfernter Ger&auml;te kommen! Nach einem Ger&auml;tescan wird das
    Attribut wieder auf <b>1</b> zur&uuml;ckgesetzt.<br></li>

    <a name="autoextend_setList"></a>
    <li>autoextend_setList {0|1}<br>
    F&uuml;r den Connector irrelevant. Default ist <b>0</b> (aus).<br>
    Bei einem Wert von <b>1</b> werden alle beim Ger&auml;testatus erkanntens
    Einstellm&ouml;glichkeiten, welche noch nicht mittels setList bekannt sind,
    hinzugef&uuml;gt.<br></li>

    <a name="brief_readings"></a>
    <li>brief_readings<br>
    F&uuml;r den Connector irrelevant. Default ist <b>1</b> (an).<br>
    Ist dieser Wert an (<b>1</b>), werden die aus der Cloud bezogenen Namen
    der einzelnen Readings nach fixen Regeln gek&uuml;rzt, was die Lesbarkeit
    der Readingnamen deutlich verbessert.<br>
    Eine Deaktivierung dieses Attributs f&uuml;hrt zu l&auml;ngeren, aber
    daf&uuml;r 100%ig eindeutigen Readingnamen. Wenn erwartete Reading vermisst
    werden, sollte man diesen Wert &auml;ndern.<br></li>

    <a name="confirmation_delay"></a>
    <li>confirmation_delay<br>
    F&uuml;r den Connector irrelevant. Default ist <b>3</b>.<br>
    Zeit in Sekunden, die nach dem Setzen eines Wertes gewartet wird, bevor der
    Status abgefragt wird.<br></li>

    <a name="device_id"></a>
    <li>device_id<br>
    F&uuml;r den Connector irrelevant.<br>
    Das ist die Samsung interne 32-Hexadezimal-Zeichen Ger&auml;tekennung. Sie
    wird beim Ger&auml;tescan in die Readings des Connectors geschrieben.<br>
    Dieses Attribut wird bei der automatischen Erstellung durch den Connector
    gesetzt und bedarf keiner Anpassung durch den Nutzer.<br></li>

    <a name="device_name"></a>
    <li>device_name<br>
    F&uuml;r den Connector irrelevant.<br>
    This is the Samsung internal device name.<br>
    Dieses Attribut wird bei der automatischen Erstellung durch den Connector
    gesetzt und bedarf keiner Anpassung durch den Nutzer.<br></li>

    <a name="device_type"></a>
    <li>device_type
    {CONNECTOR|refrigerator|freezer|washer|dryer|TV|vacuumCleaner}<br>
    Der Default ist <b>CONNECTOR</b>.<br>
    Hiermit wird der physische Ger&auml;tetyp des FHEM Ger&auml;tes gesetzt.<br>
    Der Ger&auml;tetyp <b>CONNECTOR</b> ist dem Connector vorbehalten.<br>
    Jeder Ger&auml;tetyp bekommt bei der Erstellung einen anderen Satz an
    F&auml;higkeiten, der zu unterschiedlichen Readings und v.a.
    unterschiedlichen Befehlen f&uuml;r das set Kommando f&uuml;hren.<br>
    Dieses Attribut wird bei der automatischen Erstellung durch den Connector
    gesetzt und bedarf keiner Anpassung durch den Nutzer.<br></li>

    <a name="disable"></a>
    <li>disable {0|1}<br>
    Der Default ist <b>0</b> (aus).<br>
    Bei einem Wert von <b>1</b> wird die Cloud nicht mehr zyklisch
    abgefragt.<br></li>

    <a name="discard_units"></a>
    <li>discard_units {0|1}<br>
    F&uuml;r den Connector irrelevant. Der Default ist <b>1i</b>.<br>
    Wird dieser Wert auf <b>0</b> gesetzt, werden alle Readings inclusive der
    von Samsung zurVerf&uuml;gung gestellten Einheiten gespeichert, was nicht
    dem Standardverhalten von FHEM entspricht.<br>
    Daher sollte dieser Wert nur kurzzeitig (z.B. bei Ungewissheit &uuml;ber
    die Einheit eines Readings) auf <b>0</b> gesetzt werden.<br></li>

    <a name="get_timeout"></a>
    <li>get_timeout<br>
    Der Default ist 10 Sekunden.<br>
    Dieser Wert bestimmt den Timeout f&uuml;r Abfragen aus der Samsung Cloud.
    Bei hohen Werten im Reading get_timeouts sollte hier der Wert erh&ouml;ht
    werden.<br>
    Zu hohe Werte k&ouml;nnen zum zeitweisen Einfrieren von FHEM
    f&uuml;hren.<br></li>

    <a name="interval"></a>
    <li>interval<br>
    F&uuml;r den Connector ist der Default <b>86400</b> (1 Tag).<br>
    F&uuml;r die physischen Ger&auml;te ist der Default <b>300</b> (5
    Minuten).<br>
    Hierbei handelt es sich um den Auffrischungszyklus in Sekunden.<br></li>

    <a name="IODev"></a>
    <li>IODev<br>
    F&uuml;r den Connector irrelevant.<br>
    Dieser Wert enth&auml;lt den Namen des Connector Ger&auml;ts.<br>
    Dieses Attribut wird bei der automatischen Erstellung durch den Connector
    gesetzt und bedarf keiner Anpassung durch den Nutzer.<br></li>

    <a name="readings_map"></a>
    <li>readings_map<br>
    F&uuml;r den Connector irrelevant.<br>
    Mittels dieser Liste k&ouml;nnen Befehlen lesbare Optionen zugewiesen
    werden.<br>
    Das Format ist:<br>
    <code>Reading:Value=Display[,Value=Display]</code><br></li>

    <a name="setList"></a>
    <li>setList<br>
    F&uuml;r den Connector irrelevant.<br>
    Diese Liste beinhaltet alle set Befehle mit deren Optionen.<br></li>

    <a name="setList_static"></a>
    <li>setList_static<br>
    F&uuml;r den Connector irrelevant.<br>
    Diese Liste beinhaltet initial alle durch SST für diesen Ger&auml;teetyp
    vordefinierten set Befehle mit deren Optionen. Bei x_options L&auml;ufen
    werden diese Einträge in setList &uuml;berf&uuml;hrt.<br></li>

    <a name="set_timeout"></a>
    <li>set_timeout<br>
    Der Default ist 15 Sekunden.<br>
    Dieser Wert bestimmt den Timeout f&uuml;r in die Samsung Cloud zu sendende
    Befehle. Bei hohen Werten im Reading set_timeouts sollte hier der Wert
    erh&ouml;ht werden.<br>
    Zu hohe Werte k&ouml;nnen zum zeitweisen Einfrieren von FHEM
    f&uuml;hren.<br></li>

  </ul><br>

  <a name="SSTreadings"></a>
  <b>Readings</b>
  <ul>

    <a name="devices"></a>
    <li>device_.*<br>
    Diese Readings werden im CONNECTOR f&uuml;r jedes &uuml;ber den Samsung
    SmartThings Cloud Dienst erkannte Endger&auml;t erzeut, und enthalten
    entweder den FHEM Ger&auml;tenamen oder <b>new</b>, falls das Ger&auml;t
    noch nicht in FHEM angelegt wurde. Setzt man den Wert auf etwas anderes
    (z.B. <b>nogo</b>), wird dieses Ger&auml;t bei auf 1 gesetztem
    <b>autocreate</b> nicht angelegt.<br></li>

    <a name="get_timeouts"></a>
    <li>get_timeouts<br>
    Dieses Reading zeigt, wie oft und wann zum letzten Mal die Abfrage der
    Samsung SmartThings Cloud wegen Timeouts fehlgeschlagen ist.<br></li>

    <a name="get_timeouts_row"></a>
    <li>get_timeouts_row<br>
    Dieses Reading zeigt, wie oft hintereinander die Abfrage der Samsung
    SmartThings Cloud aktuell wegen Timeouts fehlgeschlagen ist.<br>
    Nach erfolgreicher Kommunikation wird dieser Wert
    zur&uuml;ckgesetzt.<br></li>

    <a name="lastrun"></a>
    <li>lastrun<br>
    Dieses Reading zeigt, wann der CONNECTOR zuletzt erfolgreich Informationen
    aus der Samsung SmartThings Cloud abgerufen hat.<br></li>

    <a name="set_timeouts"></a>
    <li>set_timeouts<br>
    Dieses Reading zeigt, wie oft und wann zum letzten Mal das Absetzten eines
    Befehls in der Samsung SmartThings Cloud wegen Timeouts fehlgeschlagen
    ist.<br></li>

    <a name="set_timeouts_row"></a>
    <li>set_timeouts_row<br>
    Dieses Reading zeigt, wie oft hintereinander das Absetzten eines Befehls
    in der Samsung SmartThings Cloud aktuell wegen Timeouts fehlgeschlagen
    ist.<br>
    Nach erfolgreicher Kommunikation wird dieser Wert
    zur&uuml;ckgesetzt.<br></li>

    <a name="other"></a>
    <li>andere Readings<br>
    Alle anderen Readings der Endger&auml;te repr&auml;sentieren eine
    Capability, wie Samsung es nennt. Diese Readings unterscheiden sich
    deutlich zwischen den einzelnen Ger&auml;tetypen, weshalb hier nicht weiter
    auf sie eingegangen
    wird.<br></li>

  </ul><br>

</ul><br>

=end html_DE

=cut

