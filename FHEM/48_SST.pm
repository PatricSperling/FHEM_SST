################################################################################
# 48_SST.pm
#   Version 0.7.16 (2020-09-29)
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
        'device_id',
        'device_name',
        'device_type:CONNECTOR,refrigerator,freezer,TV,washer,dryer,vacuumCleaner,room_a_c',
        'disable:1,0',
        'discard_units:0,1',
        'get_timeout',
        'interval',
        'IODev',
        'setList',
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

    # differ device types
    if( $attr{$aArguments[0]}{device_type} eq 'CONNECTOR' ){
        # if we're in a redefine, don't set any defaults
        unless( defined $hash->{TOKEN} ){
            $hash->{TOKEN} = $tokenOrDevice;
            $def_interval = 86400 if $def_interval < 0;
            $attr{$aArguments[0]}{interval} = $def_interval;
            $attr{$aArguments[0]}{icon}  = 'it_server';
            $attr{$aArguments[0]}{icon}  = 'samsung_smartthings';
        }
        delete $attr{$aArguments[0]}{IODev};
        delete $attr{$aArguments[0]}{setList};
    }else{
        # if we're in a redefine, don't set any defaults
        unless( defined $attr{$aArguments[0]}{device_id} ){
            $def_interval = 300 if $def_interval < 0;
            $attr{$aArguments[0]}{interval} = $def_interval;
            $attr{$aArguments[0]}{device_id} = $tokenOrDevice if $tokenOrDevice;
            # ENTRYPOINT new device types (3/4)
            if( lc $attr{$aArguments[0]}{device_type} eq 'refrigerator' ){
                $attr{$aArguments[0]}{icon}          = 'samsung_sidebyside';
                $attr{$aArguments[0]}{setList}       = 'fridge_temperature rapidCooling:off,on rapidFreezing:off,on defrost:on,off waterFilterResetType:noArg';
                $attr{$aArguments[0]}{stateFormat}   = "cooler_temperature °C (cooler_contact)<br>\nfreezer_temperature °C (freezer_contact)";
                $attr{$aArguments[0]}{discard_units} = 1;
            }elsif( lc $attr{$aArguments[0]}{device_type} eq 'tv' ){
                $attr{$aArguments[0]}{icon}        = 'it_television';
                $attr{$aArguments[0]}{setList}     = 'power:off,on,inbetween';
                $attr{$aArguments[0]}{stateFormat} = 'switch<br>tvChannel';
            }elsif( lc $attr{$aArguments[0]}{device_type} eq 'washer' ){
                $attr{$aArguments[0]}{icon}        = 'scene_washing_machine';
                $attr{$aArguments[0]}{setList}     = 'washerMode:regular,heavy,rinse,spinDry state:pause,run,stop';
                $attr{$aArguments[0]}{stateFormat} = 'machineState<br>washerJobState';
            }elsif( lc $attr{$aArguments[0]}{device_type} eq 'room_a_c' ){
                $attr{$aArguments[0]}{icon}        = 'samsung_ac';
                $attr{$aArguments[0]}{stateFormat} = 'airConditionerMode';
            }elsif( lc $attr{$aArguments[0]}{device_type} eq 'vacuumCleaner' ){
                $attr{$aArguments[0]}{icon}    = 'vacuum_top';
                $attr{$aArguments[0]}{setList} = 'recharge:noArg turbo:on,off,silence mode:auto,part,repeat,manual,stop,map';
            }else{
                $attr{$aArguments[0]}{icon} = 'unknown';
            }
        }
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

    # differ on specific get command
    my $name = shift @aArguments;
    my $command  = shift @aArguments;
    if( $command eq 'device_list' ){
        return SST_getDeviceDetection($hash->{NAME} );
    }elsif( $command eq 'status' or $command eq 'x_options' ){
        return SST_getDeviceStatus( $hash->{NAME}, $command );
    }else{
        if( AttrVal( $name, 'device_type', 'CONNECTOR' ) eq 'CONNECTOR' ){
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

    # exit if reading not defined in setList
    # TODO

    # split up communication path
    my ($component, $capability, $module) = split( '_', $hash->{'.R2CCC'}->{$reading} );
    Log3 $hash, 4, "SST ($device): set $component/$capability - $module/" . join( ',', @aArguments );

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
            # this might be a wild guess, but if it's a number, use a number
            push @{ $data->{commands}->[0]->{arguments} }, int $aArguments[$i];
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
        SST_getDeviceStatus($hash->{NAME}, 'status');
        return "Updating $capability may have failed due to timeout." if AttrNum($device, 'verbose', 3) >= 4;
    }elsif( $jsondata->content !~ m/^\{"/ ){
        Log3 $hash, 2, "SST ($device): set $component/$capability - failed: cloud did not answer with JSON string:\n" . $jsondata->content;
        $hash->{STATE} = 'cloud return data error';
        return "Samsung SmartThings did not return valid JSON data string.\nPlease check log file for detailed information if this error persists.";
    }

    # reset timeout counter if neccessarry
    readingsSingleUpdate($hash, 'set_timeouts_row', 0, 1) if ReadingsNum($device, 'set_timeouts_row', 0);

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
            $msg = 'Variable set.';
            #$msg = undef;
        }else{
            Log3 $hash, 3, "SST ($device): set $component/$capability - did not fail with response:\n" . $jsondata->content;
            $msg = "Command has results:\n$jsoncmd\n" . $jsondata->content;
        }
    }else{
        Log3 $hash, 3, "SST ($device): set $component/$capability - did neither fail nor was successful with response:\n" . $jsondata->content;
        $msg = "Command unambigious:\n$jsoncmd\n" . $jsondata->content;
    }

    # update readings
    SST_getDeviceStatus($hash->{NAME}, 'status');
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
    readingsSingleUpdate($hash, 'get_timeouts_row', 0, 1);

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
                    $subdevicetype = lc($1);
                }elsif( $items->{items}[$i]->{deviceTypeName} =~ m/ OCF (.*)$/ ){
                    $subdevicetype = lc($1);
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
    my $nounits          = AttrNum($device, 'discard_units', 0);
    my $token            = undef;
    return "Cannot get $modus for the CONNECTOR device." if $device_type eq 'CONNECTOR';
    my $connector = AttrVal($device, 'IODev', undef);
    return "Could not identify IO Device for $device - please check configuration." unless $connector;
    $token = InternalVal( $connector, 'TOKEN', undef );
    return "Could not identify Samsung SmartThings token for $device - please check configuration." unless $token;

    # poll cloud for all status objects (all components)
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
    readingsSingleUpdate($hash, 'get_timeouts_row', 0, 1);

    # TODO: possibly read in some manual disabled capabilities from attribute or reading
    my $jsonhash       = decode_json($jsondata->content);
    my @setListHints   = ();
    my %ccc2cmd        = ();
    my @disabled       = ();
    my %readings       = ();
    my $brief_readings = AttrNum($device, 'brief_readings', 1);

    # parse JSON struct
    Log3 $hash, 5, "SST ($device): get $modus - received JSON data";
    foreach my $baselevel ( keys %{ $jsonhash } ){
        unless( $baselevel eq 'components' ){
            Log3 $hash, 4, "SST ($device): get $modus - unexpected branch: $baselevel";
            next;
        }
        foreach my $component ( keys %{ $jsonhash->{$baselevel} } ){
            foreach my $capability ( keys %{ $jsonhash->{$baselevel}->{$component} } ){
                Log3 $hash, 5, "SST ($device): get $modus - parsing component: $component";

                if( $capability eq 'execute' ){
                    # we currently don't want readings for commands
                    next;
                }elsif( $capability eq 'custom.disabledCapabilities' ){
                    if( defined $jsonhash->{$baselevel}->{$component}->{$capability}->{disabledCapabilities}->{value} ){
                        # store it for later
                        foreach ( @{ $jsonhash->{$baselevel}->{$component}->{$capability}->{disabledCapabilities}->{value} } ){
                            push( @disabled, $component . '_' . $_ );
                        }
                    }
                    next;
                }

                if( ref $jsonhash->{$baselevel}->{$component}->{$capability} eq 'HASH' ){
                    foreach my $module ( keys %{ $jsonhash->{$baselevel}->{$component}->{$capability} } ){
                        Log3 $hash, 5, "SST ($device): get $modus - parsing module: $module";
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
                                    $ccc2cmd{$reading} = join( ',', @{ $jsonhash->{$baselevel}->{$component}->{$capability}->{$module}->{value} } );
                                    next;
                                }

                                if( ref $jsonhash->{$baselevel}->{$component}->{$capability}->{$module}->{value} eq 'HASH' ){
                                    # multiple values (HASHes)
                                    foreach my $subval ( keys %{ $jsonhash->{$baselevel}->{$component}->{$capability}->{$module}->{value} } ){
                                        $thisvalue = $jsonhash->{$baselevel}->{$component}->{$capability}->{$module}->{value}->{$subval};

                                        # recalculate timestamps
                                        $thisvalue = FmtDateTime( fhemTimeGm( $6, $5, $4, $3, $2 - 1, $1 - 1900 ) )
                                            if $thisvalue =~ m/^([0-9]{4})-([0-9]{2})-([0-9]{2})T([012][0-9]):([0-5][0-9]):([0-5][0-9])\..*Z/;

                                        # remember reading
                                        my $subreading = makeReadingName( $reading . '-' . $subval );
                                        $readings{$subreading} = $thisvalue;
                                    }
                                }else{
                                    $thisvalue = $jsonhash->{$baselevel}->{$component}->{$capability}->{$module}->{value};

                                    # recalculate timestamps
                                    $thisvalue = FmtDateTime( fhemTimeGm( $6, $5, $4, $3, $2 - 1, $1 - 1900 ) )
                                        if $thisvalue =~ m/^([0-9]{4})-([0-9]{2})-([0-9]{2})T([012][0-9]):([0-5][0-9]):([0-5][0-9])\..*Z/;

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
                                next unless defined $jsonhash->{$baselevel}->{$component}->{$capability}->{$module}->{$attribute}; # ... or empty elements
                                Log3 $hash, 3, "SST ($device): get $modus - unexpected hash reading at attribute level: $baselevel/$component/$capability/$module/$attribute of type " . ref( $jsonhash->{$baselevel}->{$component}->{$capability}->{$module}->{$attribute} );
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
    Log3 $hash, 5, "SST ($device): get $modus - identified disabled components:\n" . Dumper( @disabled );
    Log3 $hash, 5, "SST ($device): get $modus - identified readings:\n" . Dumper( %readings );
    Log3 $hash, 5, "SST ($device): get $modus - identified setList options:\n" . Dumper( @setListHints );

    # create/update all readings
    if( $modus eq 'status' ){
        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, 'setList_hint', join( ' ', @setListHints ), 1 ) if $#setListHints >= 0;
        EACHREADING: foreach my $key ( keys %readings ){
            my $reading = $key;
            foreach (@disabled){
                my $regex = '^' . $_ . '_';
                next EACHREADING if $key =~ m/$regex/;
            }
            if( $brief_readings ){
                $reading =~ s/_[^_]+_/_/; # remove middle part (capability)
                $reading =~ s/^main_//i;  # remove main component
            }
            readingsBulkUpdate( $hash, $reading, $readings{$key}, 1 );
        }
        readingsEndUpdate($hash, 1);
    }

    # store reading name mapping
    if( $modus ne 'status' or not defined $hash->{'.R2CCC'} ){
        # filling setList
        my %rdn2ccc=();
        my $setList = '';
        EACHREADING: foreach my $key ( keys %readings ){
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
                $setList .= " $reading:on,off"; 
                #$setList .= " $reading:On,Off"; 
            }elsif( $key =~ m/Setpoint$/ ){
                $setList .= " $reading"; 
            }
        }
        $hash->{'.R2CCC'} = { %rdn2ccc };
        if( $modus eq 'x_options' ){
            $setList =~ s/^ //;
            $attr{$device}{setList} = $setList;
        }
        return undef;
    }

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
=item summary    Integration of Samsung SmartThings devices
=item summary_DE Einbindung von Samsung SmartThings Geräten
=begin html

<br>
<a name="SST"></a>
<h3>SST - Samsung SmartThings Connector</h3>
<ul>
  <b>Please Note that this Module is currently in an early beta status. Not
  everything already works as described!<b><br>
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
    <code>define &lt;name&gt; SST &lt;device type&gt; IODev=&lt;connector device&gt;</code><br>
    <br>
    You need to give the <i>SmartThings token</i> which must be generated on <a 
    href="https://account.smartthings.com/tokens" 
    target='_blank'>https://account.smartthings.com/tokens</a>. The creation of
    the real devices also requires the <i>device type</i> which is usually
    identified and created as a reading by the device_list command.<br>
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
    created.<br>

    <a name="status"></a>
    <li>status<br>
    This is not available for the connector device and will refresh the list
    of available/useful SmartThings capabilities in the readings. The readings
    may differ greatly between different types of devices.<br>

    <a name="x_options"></a>
    <li>x_options<br>
    This is not available for the connector device and will overwrite the
    setList attribute with the corresponding information taken from the
    device's cloud response.<br>

  </ul><br>

  <a name="SSTattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="autocreate"></a>
    <li>autocreate {0|1|2}<br>
    Only valid for connector device. Defaults to <b>0</b> (off).<br>
    If set to <b>0</b> no individual devices will be created on device detection.<br>
    If set to <b>1</b> only uncreated devices will be created on device detection.<br>
    If set to <b>2</b> all devices will be recreated (this may produce errors due to
    previously undeleted devices) on device detection. After the
    detection/creation the value for <b>autocreate</b> is automatically reset
    to <b>1</b>.<br>

    <a name="autoextend_setList"></a>
    <li>autoextend_setList {0|1}<br>
    Not valid for connector device. Defaults to <b>0</b> (off).<br>
    If set to <b>1</b> all setting options identified during a status update that are
    not yet defined in setList will be written into the setList attribute.<br>

    <a name="brief_readings"></a>
    <li>brief_readings<br>
    Not valid for connector device. Defaults to <b>1</b> (on).<br>
    If set to <b>1</b> the cloud reading names will be abbreviated resulting in
    far more readable reading names.<br>
    If set to <b>0</b> these names will remain as received. Only this way
    unique names can be guaranteed. Use this if you think you miss some
    readings.<br>

    <a name="device_id"></a>
    <li>device_id<br>
    Not valid for connector device.<br>
    This is the 32 digits hexadecimal Samsung internal device ID token. To
    obtain it run the device detection and take it from the readings.<br>
    This attribute is automatically filled on device generation and usually
    does not require your attention.<br>

    <a name="device_name"></a>
    <li>device_name<br>
    Not valid for connector device.<br>
    This is the Samsung internal device name.<br>
    This attribute is automatically filled on device generation and usually
    does not require your attention.<br>

    <a name="device_type"></a>
    <li>device_type {CONNECTOR|refrigerator|freezer|washer|dryer|TV|vacuumCleaner}<br>
    Defaults to <b>CONNECTOR</b>.<br>
    This specifies the physical device type of this FHEM device.<br>
    A 'special' device type is <b>CONNECTOR</b> which is the instance for device
    detection and creation.<br>
    Each different device type has a different set of capabilities that will
    result in the different readings and options for the setList.
    This attribute is automatically filled on device generation and usually
    does not require your attention.<br>

    <a name="disable"></a>
    <li>disable {0|1}<br>
    Defaults to 0 (off).<br>
    A value of <b>1</b> disables auto-polling of device_list or status.

    <a name="discard_units"></a>
    <li>discard_units {0|1}<br>
    Not valid for connector device. Defaults to <b>0</b> (off).<br>
    If set to <b>1</b> all readings (aka Samsung capabilities) will be stored
    without any units. This might be helpful as Samsung i.e. does not provide
    the degree symbol for temperatures, resulting in readings like <b>4 C</b>
    instead of <b>4 °C</b>.<br>

    <a name="get_timeout"></a>
    <li>get_timeout<br>
    Defaults to 10 seconds.
    This is the timeout for cloud get requests in seconds. If your get_timeouts
    reading gets excessive, increase this value.<br>
    Values too high might freeze FHEM on bad internet connections.<br>

    <a name="interval"></a>
    <li>interval<br>
    Defaults to <b>86400</b> (1 day) for the connector.<br>
    Defaults to <b>300</b> (5 minutes) for the physical devices.<br>
    This is the reload interval in seconds.<br>

    <a name="IODev"></a>
    <li>IODev<br>
    Not valid for connector device.<br>
    This is usually set on define and will allow you to identify connected
    devices from the connector device. It is also used for delting all pysical
    devices when deleting the connector device.<br>
    This attribute is automatically filled on device generation and usually
    does not require your attention.<br>

    <a name="setList"></a>
    <li>setList<br>
    Not valid for connector device.<br>
    This is the list of set commands available for your device (type). There
    is a default which is set on device creation based on the device type.<br>
    If you feel this list is not correct, please inform the module owner for
    change requests to the default.<br>
    If autoextend_setList is set, this list may grow on status updates.<br>

    <a name="set_timeout"></a>
    <li>set_timeout<br>
    Defaults to 15 seconds.
    This is the timeout for cloud set requests in seconds. If your set_timeouts
    reading gets excessive, increase this value.<br>
    Values too high might freeze FHEM on bad internet connections.<br>

  </ul><br>

  <a name="SSTreadings"></a>
  <b>Readings</b>
  <ul>

    <a name="devices"></a>
    <li>device_.*<br>
    These readings are created for the CONNECTOR for each client device
    identified from the Samsung SmartThings cloud service.<br>

    <a name="lastrun"></a>
    <li>lastrun<br>
    This reading is set for the CONNECTOR each time it successfully retrieves
    information from the Samsung SmartThings cloud service.<br>

    <a name="timeount_counter"></a>
    <li>timeount_counter<br>
    This reading shows how often the retieval of information from the Samsung
    SmartThings cloud service fails and when it did fail last.<br>

    <a name="other"></a>
    <li>other readings<br>
    All other readings for physical devices represent one, as Samsung calls
    them, capability. These capabilities vary greatly from device type to
    device type, so we cannot explain them here.<br>

  </ul><br>

</ul><br>

=end html

=begin html_DE

<br>
<a name="SST"></a>
<h3>SST - Samsung SmartThings Connector</h3>
<ul>
  Bitte beachten Sie, daß sich dieses Modul in einem frühen Beta-Stadium
  befindet. Noch nicht alles funktioniert wie beschrieben!<br>
  SST ist eine generische Modul zur Einbindung von Samsung SmartThings und den
  dort eingebundenen Geräten. Hiermit können alle SmartThings Geräte aus der
  Cloud eingelesen werden, und ihre FHEM Pendents angelegt werden. Die
  erzeugten Geräte können dann in FHEM angezeigt und gesteuert werden.<br>
  <br>

  <a name="SSTdefine"></a>
  <b>Define</b>
  <ul>
    <li><b>Connector</b>:<br>
    <code>define &lt;name&gt; SST &lt;SmartThings token&gt;</code><br>
    <br>
    Zur Anlage des Connectors ist das <b>SmartThings token</b> nötig, welches
    zunächst unter <a href="https://account.smartthings.com/tokens" 
    target='_blank'>https://account.smartthings.com/tokens</a> erstellt werden
    muß. Dieses Modul benötigt ein Token mit mindestens dem Zugriff auf Geräte
    und Geräteprofile.<br>
    <br>

    <li><b>Phyische Geräte</b>:<br>
    <code>define &lt;name&gt; SST &lt;device type&gt; IODev=&lt;connector device&gt;</code><br>
    <br>
    <b>Sinnvollerweise überläßt man diese Erstellung dem Connector.</b><br>
    Die Erstellung der FHEM Geräte für die physischen Geräte bedarf nur der
    Angabe des <b>device type</b>, über den die z.B. die möglichen set
    Befehle vordefiniert werden, sowie des <b>IODev</b>, welches auf den
    Connector verweisen muß.<br>
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
    Diese Funktion steht nur beim Connector zur Verfügung.<br>
    Hierüber wird der Gerätescan gestartet, der dann sämtliche gefundnen
    SmartThings Geräte in Readings schreibt.<br>
    Wenn <i>autocreate</i> (s.u.) gesetzt ist, werden die entsprechenden FHEM
    Geräte angelegt.<br>

    <a name="status"></a>
    <li>status<br>
    Diese Funktion steht beim Connector nicht zur Verfügung.<br>
    Hierüber wird der Gerätestatus über die Cloud abgefragt und in Readings
    geschrieben. Die verfügbaren Readings unterscheiden sich stark zwischen
    verschiedenen Gerätetypen.<br>

    <a name="x_options"></a>
    <li>x_options<br>
    Diese Funktion steht beim Connector nicht zur Verfügung.<br>
    Hierüber wird eine Liste möglicher Kommandos aus dem Gerätestatus der
    Cloud erzeugt und in dem Attribut setList gespeichert.<br>

  </ul><br>

  <a name="SSTattr"></a>
  <b>Attributes</b>
  <ul>

    <a name="autocreate"></a>
    <li>autocreate {0|1|2}<br>
    Nur für den Connector relevant. Default ist <b>0</b> (aus).<br>
    Bei einem Wert von <b>0</b> werden keine Geräte durch den Gerätescan
    angelegt.<br>
    Bei einem Wert von <b>1</b> werden nur neue, noch nicht angelegte Geräte
    durch den Gerätescan angelegt.<br>
    Bei einem Wert von <b>2</b> werden alle gefundenen Geräte durch den
    Gerätescan angelegt. Hierbei kann es zu Fehlermeldungen wegen zuvor nicht
    entfernter Geräte kommen! Nach einem Gerätescan wird das Attribut wieder
    auf <b>1</b> zurückgesetzt.<br>

    <a name="autoextend_setList"></a>
    <li>autoextend_setList {0|1}<br>
    Für den Connector irrelevant. Default ist <b>0</b> (aus).<br>
    Bei einem Wert von <b>1</b> werden alle beim Gerätestatus erkanntens
    Einstellmöglichkeiten, welche noch nicht mittels setList bekannt sind,
    hinzugefügt.<br>

    <a name="brief_readings"></a>
    <li>brief_readings<br>
    Für den Connector irrelevant. Default ist <b>1</b> (an).<br>
    Ist dieser Wert an (<b>1</b>), werden die aus der Cloud bezogenen Namen
    der einzelnen Readings nach fixen Regeln gekürzt, was die Lesbarkeit der
    Readingnamen deutlich verbessert.<b>
    Eine Deaktivierung dieses Attributs führt zu längeren, aber dafür 100%ig
    eindeutigen Readingnamen. Wenn erwartete Reading vermisst werden, sollte
    man diesen Wert ändern.<br>

    <a name="device_id"></a>
    <li>device_id<br>
    Für den Connector irrelevant.<br>
    Das ist die Samsung interne 32-Hexadezimal-Zeichen Gerätekennung. Sie wird
    beim Gerätescan in die Readings des Connectors geschrieben.<br>
    Dieses Attribut wird bei der automatischen Erstellung durch den Connector
    gesetzt und bedarf keiner Anpassung durch den Nutzer.<br>

    <a name="device_name"></a>
    <li>device_name<br>
    Für den Connector irrelevant.<br>
    This is the Samsung internal device name.<br>
    Dieses Attribut wird bei der automatischen Erstellung durch den Connector
    gesetzt und bedarf keiner Anpassung durch den Nutzer.<br>

    <a name="device_type"></a>
    <li>device_type {CONNECTOR|refrigerator|freezer|washer|dryer|TV|vacuumCleaner}<br>
    Der Default ist <b>CONNECTOR</b>.<br>
    Hiermit wird der physische Gerätetyp des FHEM Gerätes gesetzt.<br>
    Der Gerätetyp <b>CONNECTOR</b> ist dem Connector vorbehalten.<br>
    Jeder Gerätetyp bekommt bei der Erstellung einen anderen Satz an
    Fähigkeiten, der zu unterschiedlichen Readings und v.a. unterschiedlichen
    Befehlen für das set Kommando führen.<br>
    Dieses Attribut wird bei der automatischen Erstellung durch den Connector
    gesetzt und bedarf keiner Anpassung durch den Nutzer.<br>

    <a name="disable"></a>
    <li>disable {0|1}<br>
    Der Default ist 0 (aus).<br>
    Bei einem Wert von <b>1</b> wird die Cloud nicht mehr zyklisch abgefragt.<br>

    <a name="discard_units"></a>
    <li>discard_units {0|1}<br>
    Für den Connector irrelevant.<br>
    Bei einem Wert von <b>1</b> werden alle Readings ohne ggf. von Samsung zur
    Verfügung gestellte Einheiten gesetzt. Das kann hilfreich sein, wenn
    Temperaturen abgefragt werden, da hier sonst Readings wie <b>4 C</b>
    erzeugt werden, anstatt <b>4 °C</b>.<br>

    <a name="get_timeout"></a>
    <li>get_timeout<br>
    Der Default ist 10 Sekunden.<br>
    Dieser Wert bestimmt den Timeout für Abfragen aus der Samsung Cloud. Bei
    hohen Werten im Reading get_timeouts sollte hier der Wert erhöht werden.<br>
    Zu hohe Werte können zum zeitweisen Einfrieren von FHEM führen.<br>

    <a name="interval"></a>
    <li>interval<br>
    Für den Connector ist der Default <b>86400</b> (1 Tag).<br>
    Für die physischen Geräte ist der Default <b>300</b> (5 Minuten).<br>
    Hierbei handelt es sich um den Auffrischungszyklus in Sekunden.<br>

    <a name="IODev"></a>
    <li>IODev<br>
    Für den Connector irrelevant.<br>
    Dieser Wert enthält den Namen des Connector Geräts.<br>
    Dieses Attribut wird bei der automatischen Erstellung durch den Connector
    gesetzt und bedarf keiner Anpassung durch den Nutzer.<br>

    <a name="setList"></a>
    <li>setList<br>
    Not valid for connector device.<br>
    This is the list of set commands available for your device (type). There
    is a default which is set on device creation based on the device type.<br>
    If you feel this list is not correct, please inform the module owner for
    change requests to the default.<br>
    If autoextend_setList is set, this list may grow on status updates.<br>

    <a name="set_timeout"></a>
    <li>set_timeout<br>
    Der Default ist 15 Sekunden.<br>
    Dieser Wert bestimmt den Timeout für in die Samsung Cloud zu sendende
    Befehle. Bei hohen Werten im Reading set_timeouts sollte hier der Wert
    erhöht werden.<br>
    Zu hohe Werte können zum zeitweisen Einfrieren von FHEM führen.<br>

  </ul><br>

  <a name="SSTreadings"></a>
  <b>Readings</b>
  <ul>

    <a name="devices"></a>
    <li>device_.*<br>
    Diese Readings werden im CONNECTOR für jedes über den Samsung SmartThings
    Cloud Dienst erkannte Endgerät erzeut, und enthalten entweder den FHEM
    Gerätenamen oder <b>new</b>, falls das Gerät noch nicht in FHEM angelegt
    wurde. Setzt man den Wert auf etwas anderes (z.B. <b>nogo</b>), wird dieses
    Gerät bei auf 1 gesetztem <b>autocreate</b> nicht angelegt.<br>

    <a name="get_timeouts"></a>
    <li>get_timeouts<br>
    Dieses Reading zeigt, wie oft und wann zum letzten Mal die Abfrage der
    Samsung SmartThings Cloud wegen Timeouts fehlgeschlagen ist.<br>

    <a name="get_timeouts_row"></a>
    <li>get_timeouts_row<br>
    Dieses Reading zeigt, wie oft hintereinander die Abfrage der Samsung
    SmartThings Cloud aktuell wegen Timeouts fehlgeschlagen ist.<br>
    Nach erfolgreicher Kommunikation wird dieser Wert zurückgesetzt.<br>

    <a name="lastrun"></a>
    <li>lastrun<br>
    Dieses Reading zeigt, wann der CONNECTOR zuletzt erfolgreich Informationen
    aus der Samsung SmartThings Cloud abgerufen hat.<br>

    <a name="set_timeouts"></a>
    <li>set_timeouts<br>
    Dieses Reading zeigt, wie oft und wann zum letzten Mal das Absetzten eines
    Befehls in der Samsung SmartThings Cloud wegen Timeouts fehlgeschlagen
    ist.<br>

    <a name="set_timeouts_row"></a>
    <li>set_timeouts_row<br>
    Dieses Reading zeigt, wie oft hintereinander das Absetzten eines Befehls
    in der Samsung SmartThings Cloud aktuell wegen Timeouts fehlgeschlagen
    ist.<br>
    Nach erfolgreicher Kommunikation wird dieser Wert zurückgesetzt.<br>

    <a name="other"></a>
    <li>andere Readings<br>
    Alle anderen Readings der Endgeräte repräsentieren eine Capability, wie
    Samsung es nennt. Diese Readings unterscheiden sich deutlich zwischen den
    einzelnen Gerätetypen, weshalb hier nicht weiter auf sie eingegangen
    wird.<br>

  </ul><br>

=end html

=cut

