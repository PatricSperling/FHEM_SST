################################################################################
# 48_SST.pm
#   Version 0.7.0 (2020-09-12)
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
# key: FHEM command
# element 0: SmartThings capability
# element 1: SmartThings set command
# element 2: set data type (enum|number|string|vector3|colormap|null)
# element 3: enum: comma sperated list
#            number: min,max
#            vector3: x,y,z
#            colormap: hue,saturation
my %SST_commands = (
	'fridge_temperature' => [
        'refrigerationSetpoint',
        'setRefrigerationSetpoint',
        'number',
        '-460,10000'
	],
	'fridge_power_cool' => [
        'rapidCooling',
        'setRapidCooling',
        'enum',
        'off,on'
	],
	'freezer_power_freeze' => [
        'rapidFreezing',
        'setRapidFreezing',
        'enum',
        'off,on'
	],
    'cleaner_recharge' => [
		'robotCleanerMovement',
		'setRobotCleanerMovement',
		'enum',
		'homing,idle,charging,alarm,powerOff,reserve,point,after,cleaning'
	],
    'cleaner_turbo' => [
		'robotCleanerTurboMode',
		'setRobotCleanerTurboMode',
		'enum',
		'on,off,silence'
	],
    'cleaner_mode' => [
		'robotCleanerCleaningMode',
		'setRobotCleanerCleaningMode',
		'enum',
		'auto,part,repeat,manual,stop,map'
	],
);

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

    my @attrList = qw(
        autocreate:0,1,2
        autoextend_setList:1,0
        device_id
	    device_name
        device_type:CONNECTOR,refrigerator,freezer,TV,washer,dryer,vacuumCleaner
        disable:1,0
        discard_units:0,1
        interval
	    IODev
        setList
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
    $hash->{name}                      = $aArguments[0];
    #$attr{$aArguments[0]}{token}       = $aArguments[2];
    $attr{$aArguments[0]}{device_type} = '';
    $attr{$aArguments[0]}{interval}    = -1;
    my $tokenOrDevice = '';
    $attr{$aArguments[0]}{device_id}   = 'unknown';
    $attr{$aArguments[0]}{IODev}       = '';

    # on more attributes - analyze and act correctly
    my $index = 2;
    while( $index <= $#aArguments ){
        if( $aArguments[$index] =~ m/^[0-9]+$/ ){
            # numeric value -> interval
            if( $attr{$aArguments[0]}{interval} == -1 ){
                $attr{$aArguments[0]}{interval} = $aArguments[$index];
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
            #if( $attr{$aArguments[0]}{device_id} eq 'unknown' ){
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
        }elsif( $aArguments[$index] =~ m/^[A-Za-z]+$/ ){
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
        $hash->{TOKEN} = $tokenOrDevice;
        #$attr{$aArguments[0]}{token} = $tokenOrDevice;
        $attr{$aArguments[0]}{icon}  = 'it_server';
		delete $attr{$aArguments[0]}{IODev};
        delete $attr{$aArguments[0]}{setList};
        delete $attr{$aArguments[0]}{device_id};
	}else{
        $attr{$aArguments[0]}{device_id} = $tokenOrDevice if $tokenOrDevice;
    	if( lc $attr{$aArguments[0]}{device_type} eq 'refrigerator' ){
        	$attr{$aArguments[0]}{icon}          = 'fridge';
         	$attr{$aArguments[0]}{setList}       = 'fridge_temperature rapidCooling:off,on rapidFreezing:off,on defrost:on,off waterFilterResetType:noArg';
			$attr{$aArguments[0]}{stateFormat}   = "contactSensor_contact<br>temperatureMeasurement_temperature °C";
			$attr{$aArguments[0]}{discard_units} = 1;
    	}elsif( lc $attr{$aArguments[0]}{device_type} eq 'tv' ){
        	$attr{$aArguments[0]}{icon}    = 'it_television';
        	$attr{$aArguments[0]}{setList} = 'power:off,on,inbetween';
    	}elsif( lc $attr{$aArguments[0]}{device_type} eq 'washer' ){
        	$attr{$aArguments[0]}{icon}    = 'scene_washing_machine';
        	$attr{$aArguments[0]}{setList} = 'washerMode:regular,heavy,rinse,spinDry state:pause,run,stop';
    	}elsif( lc $attr{$aArguments[0]}{device_type} eq 'vacuumCleaner' ){ # TODO: is this the correct identifyer?
        	$attr{$aArguments[0]}{icon}    = 'vacuum_top';
        	$attr{$aArguments[0]}{setList} = 'recharge:noArg turbo:on,off,silence mode:auto,part,repeat,manual,stop,map';
    	}else{
			$attr{$aArguments[0]}{icon} = 'unknown';
		}
    }

    # set interval to 1 hour (connector) or 5 minutes if unset
    if( $attr{$aArguments[0]}{interval} == -1 ){
        if( $attr{$aArguments[0]}{device_type} eq 'CONNECTOR' ){
            $attr{$aArguments[0]}{interval} = 86400;
        }else{
            $attr{$aArguments[0]}{interval} = 300;
        }
    }

    Log3 $aArguments[0], 3, "SST ($aArguments[0]): SST $attr{$aArguments[0]}{device_type} defined as $aArguments[0] ($init_done)";

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
    my ($hash, $notifydevice) = @_;
    my $name   = $hash->{NAME};
    my $device = $notifydevice->{NAME}; # Device that created the events
	my $events = deviceEvents($notifydevice, 1);


    # TODO: handle CONNECTOR renaming - update client devices

    return undef if IsDisabled( $name );

    # after configuration/startup
    if( $device eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events}) ){
        SST_ProcessTimer($hash);
    }
    return undef;
}

#####################################
# UNDEFINE/DELETE
sub SST_Undefine($$) {
    my ($hash, $arg) = @_;
    RemoveInternalTimer($hash);
    # TODO: possible removal of associated devices if this is the main device - needs to be discussed
    return undef;
}

#####################################
# MAIN GET COMMAND
sub SST_Get($@) {
    my ($hash, @aArguments) = @_;
    return '"get $hash->{name}" needs at least one argument' if int(@aArguments) < 2;

    # differ on specific get command
    my $name = shift @aArguments;
    my $command  = shift @aArguments;
    if( $command eq 'device_list' ){
        return SST_getDeviceDetection($hash->{NAME});
    }elsif( $command eq 'status' ){
        return SST_getDeviceStatus( $hash->{NAME});
    }else{
        if( AttrVal( $name, 'device_type', 'CONNECTOR' ) eq 'CONNECTOR' ){
            return "Unknown argument $command, choose one of device_list:noArg";
        }else{
            return "Unknown argument $command, choose one of status:noArg";
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

    #Log3 $hash, 3, "SST ($device): SST_ProcessTimer: in function SST_ProcessTimer (i $interval / d $disabled)";

    if( $interval and not $disabled ){
        if( AttrVal( $device, 'device_type', 'CONNECTOR' ) eq 'CONNECTOR' ){
            SST_getDeviceDetection($device);
        }else{
            SST_getDeviceStatus($device);
        }
        #Log3 $hash, 3, "SST ($device): SST_ProcessTimer: reschedule " . ( gettimeofday() + $interval );
        InternalTimer( gettimeofday() + $interval, 'SST_ProcessTimer', $hash );
    }
    return undef;
}

#####################################
# MAIN SET COMMAND
sub SST_Set($@) {
    my ($hash, @aArguments) = @_;

    return '"set SST" needs at least one argument' if (int(@aArguments) < 2);

    my $name    = shift @aArguments;
    my $command = shift @aArguments;
    my $mode    = shift @aArguments;
    my $value   = join("", @aArguments);
    my $device_type  = AttrVal( $name, "device_type", 'CONNECTOR' );

    # we need this for FHEMWEB
    if( $command eq '?' ){
        return "Unknown argument $command, choose one of " if $device_type eq 'CONNECTOR';
        my $setlist = AttrVal( $name, 'setList', '' );
        return "Unknown argument $command, choose one of $setlist"; #. join(" ", keys %SST_sets);
    }

    # differ device types
    if( $device_type eq 'refrigerator' ){
        if( $command eq 'fridge_temperature' ){
            SST_sendCommand($name, 'setRefrigerationSetpoint', $mode);
        }elsif( $command eq 'rapidCooling' ){
            SST_sendCommand($name, $command, $mode);
        }else{
            return "Command '$command' is currently not supported for device type '$device_type'!";
        }
    }elsif( $device_type eq 'vacuumCleaner' ){
        if( $command eq "recharge" or $command eq "mode" or $command eq "turbo" ){
            SST_sendCommand($name, $command, $mode);
        }else{
            return "Command '$command' is currently not supported for device type '$device_type'!";
        }
    }else{
        return "Device type '$device_type' is currently not supported!";
    }
}

#####################################
# GET COMMAND: device listing/creation
sub SST_getDeviceDetection($) {
    my ($device) = @_;
    my $hash     = $defs{$device};
    return 'device detection only works on connector device' if AttrVal($device, 'device_type', 'CONNECTOR') ne 'CONNECTOR';

    # get list from cloud
    my $token    = $hash->{TOKEN};
    return "Could not identify Samsung SmartThings token for $device - please check configuration." unless $token;
    my $webget   = HTTP::Request->new('GET', 
        "https://api.smartthings.com/v1/devices/",
        ['Authorization' => "Bearer: $token"]
    );
    my $webagent = LWP::UserAgent->new();
    my $jsondata = $webagent->request($webget);
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
    $msg .= "Device-ID - Name";
    $msg .= " - Autocreation Status" if AttrNum($device, "autocreate", '0') > 0;
    $msg .= "\n\n";
    my $xxx = '';
    for(my $i = 0; $i < $count; $i++) {
        my $deviceId = $items->{items}[$i]->{deviceId};
        my $name = $items->{items}[$i]->{name};
        $msg .= "$deviceId - $name";

        if( AttrNum($device, 'verbose', '0') == 4 ){
            my $compcount = scalar @{ $items->{items}[$i]->{components} };
            for(my $j = 0; $j < $compcount; $j++) {
                $xxx .= $items->{items}[$i]->{components}[$j]->{id} . ":";
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
                Log3 $hash, 3, "SST ($device): found new client device '$deviceId'";
            }else{
                Log3 $hash, 3, "SST ($device): failed adding new client device '$deviceId'";
                next;
            }
        }else{
            Log3 $hash, 4, "SST ($device): identified already known device '$deviceId'";
        }

        if( AttrNum($device, "autocreate", '0') > 0 ){
            if( ReadingsVal($device, "device_$deviceId", '') eq 'new' or AttrNum($device, "autocreate", '0') == 2 ){
                # build (temporary/automatic) device name
                my $tmpname = $items->{items}[$i]->{deviceId};
                $tmpname =~ s/.*-/SST_/;
                $tmpname =~ s/\s//;
                if( $tmpname eq 'SST_000000000000' ){
                    $tmpname = $items->{items}[$i]->{deviceId};
                    $tmpname =~ s/[\s-]//g;
                    $tmpname =~ s/^(.{12}).*$/SST_$1/;
                }

				# try to determine the device type
                my $subdevicetype = 'unknown';
				if( $items->{items}[$i]->{name} =~ m/^\[(.*)\]/ ){
					$subdevicetype = lc($1);
				}elsif( $items->{items}[$i]->{deviceTypeName} =~ m/ OCF (.*)$/ ){
					$subdevicetype = lc($1);
				}else{
                    $msg .= "cannot determine device type from name (" . $items->{items}[$i]->{name} . ") or deviceTypeName (" . $items->{items}[$i]->{deviceTypeName} . ").";
					Log3 $hash, 2, "SST ($device): cannot determine device type from name (" . $items->{items}[$i]->{name} . ") or deviceTypeName (" . $items->{items}[$i]->{deviceTypeName} . ").";
				}

                # create new device
                # TODO: token rausschmeißen
                Log3 $hash, 2, "SST ($device): automatically adding device $tmpname";
                fhem( "define $tmpname SST $subdevicetype IO=$device" );
                if( AttrVal($tmpname, 'device_type', undef) ){
                    $msg .= " - newly created as $tmpname";
					fhem "attr $tmpname device_id " . $items->{items}[$i]->{deviceId};
                    fhem "attr $tmpname device_name " . $items->{items}[$i]->{name};
                    unless( readingsSingleUpdate($hash, "device_$deviceId", "$tmpname", 1) ){
                        Log3 $hash, 3, "SST ($device): updating reading for $deviceId failed - disabling autocreate";
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
    return $msg;
}

#####################################
# GET COMMAND: device status/details
sub SST_getDeviceStatus($) {
    my ($device)    = @_;
    my $hash        = $defs{$device};
    my $device_type = AttrVal($device, 'device_type', 'CONNECTOR');
    my $nounits     = AttrNum($device, 'discard_units', 0);
    my $token       = undef;
    if( $device_type eq 'CONNECTOR' ){
        $token = $hash->{TOKEN};
    }else{
        my $connector = AttrVal($device, 'IODev', undef);
        return "Could not identify IO Device for $device - please check configuration." unless $connector;
        # wie zur hölle komm ich da ran
        $token = InternalVal( $connector, 'TOKEN', undef );
    }
    return "Could not identify Samsung SmartThings token for $device - please check configuration." unless $token;

    # poll cloud for all status object
    my $webget   = HTTP::Request->new('GET', 
        "https://api.smartthings.com/v1/devices/" . AttrVal($device, 'device_id', undef) . "/components/main/status",
        ['Authorization' => "Bearer: $token"]
    );
    my $webagent = LWP::UserAgent->new();
    my $jsondata = $webagent->request($webget);
    unless( $jsondata->content){
        Log3 $hash, 3, "SST ($device): status retrieval failed";
        return "Could not obtain status for Samsung SmartThings Device $device.\nPlease check your configuration.";
    }
    my $jsonhash = decode_json($jsondata->content);
#Log3 $hash, 5, "SST ($device): JSON STRUCT (device status):\n".Dumper($jsonhash);
    #if( AttrNum($device, 'verbose', 0) >= 5 ){
    #my $jsondump = $jsondata->content;
    #$jsondump =~ s/[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/g;
    #Log3 $hash, 5, "SST ($device): JSON STRUCT (device status):\n$jsondump";
    #}

    # TODO: possibly read in some manual disabled capabilities from attribute or reading
    my @setListHints = ();
    my @disabled = ();
    my %readings = ();

    # parse JSON struct
    foreach my $level_0 ( keys %{ $jsonhash } ){
        Log3 $hash, 4, "SST ($device): Key0: $level_0";
        next if $level_0 eq 'execute';
        if( $level_0 eq 'custom.disabledCapabilities' ){
            push( @disabled, @{ $jsonhash->{'custom.disabledCapabilities'}->{disabledCapabilities}->{value} } ) if defined $jsonhash->{'custom.disabledCapabilities'}->{disabledCapabilities}->{value};
            next;
        }
        if( ref $jsonhash->{$level_0} eq 'HASH' ){
            foreach my $level_1 ( keys %{ $jsonhash->{$level_0} } ){
                Log3 $hash, 4, "SST ($device): Key1: $level_0 -> $level_1";
                if( ref $jsonhash->{$level_0}->{$level_1} eq 'HASH' ){
                    if( defined $jsonhash->{$level_0}->{$level_1}->{value} ){
                        my $reading = makeReadingName( $level_0 . '_' . $level_1 );
                        my $thisvalue = '';
                        if( ref $jsonhash->{$level_0}->{$level_1}->{value} eq 'ARRAY' ){
                            # this might always indicate value options... let's assume that for the time being
                            push @setListHints, "$level_0:" . join( ',', @{ $jsonhash->{$level_0}->{$level_1}->{value} } );
                            next;
                        }
                        $thisvalue = $jsonhash->{$level_0}->{$level_1}->{value};
                        if( exists $jsonhash->{$level_0}->{$level_1}->{unit} and not $nounits ){
                            $readings{$reading} = $jsonhash->{$level_0}->{$level_1}->{value} . ' ' . $jsonhash->{$level_0}->{$level_1}->{unit};
                        }else{
                            $readings{$reading} = $jsonhash->{$level_0}->{$level_1}->{value};
                        }
                        next;
                    }

                    foreach my $level_2 ( keys %{ $jsonhash->{$level_0}->{$level_1} } ){
                        next if $level_2 eq 'timestamp'; # who cares about timestamps ...
                        next unless defined $jsonhash->{$level_0}->{$level_1}->{$level_2}; # ... or empty elements
                        #next if( $level_2 eq 'value' and not defined( $jsonhash->{$level_0}->{$level_1}->{$level_2} ) );
                        Log3 $hash, 3, "SST ($device): unexpected hash reading in $level_0 -> $level_1 -> $level_2: " . ref( $jsonhash->{$level_0}->{$level_1}->{$level_2} );
                        # TODO: propably extend interpretation if someone gets even more info
                    }
                }else{
                    Log3 $hash, 3, "SST ($device): unexpected non-hash reading in $level_0 -> $level_1: " . ref( $jsonhash->{$level_0}->{$level_1} );
                }
            }
        }else{
            Log3 $hash, 3, "SST ($device): unexpected non-hash reading in $level_0: " . ref( $jsonhash->{$level_0} );
        }
    }

    # create/update all readings
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, 'setList_hint', join( ' ', @setListHints ), 1 ) if $#setListHints >= 0;
    EACHREADING: foreach my $reading ( keys %readings ){
        # remove disabled items even if they have values
        foreach (@disabled){
            my $regex = '^' . $_ . '_';
            next EACHREADING if $reading =~ m/$regex/;
        }
        readingsBulkUpdate( $hash, $reading, $readings{$reading}, undef );
    }
    readingsEndUpdate($hash, 1);

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
            Log3 $hash, 3, "SST ($device): extended setList by $updated entries";
        }
    }

    return Dumper($jsonhash) if AttrNum($device, 'verbose', 0) >= 5;
    return undef;
}

#####################################
# SET COMMAND: execute some command
sub SST_sendCommand($@) {
    # TODO: well, just about everything ;)
    my ($device, $command, $mode) = @_;
    my $hash        = $defs{$device};
    my $device_type = AttrVal($device, 'device_type', 'CONNECTOR');
    my $data        = {};
    my $capa        = '';
    my $cmd         = '';
    my $cmdargs     = '';

    # differ capabilities on device type
    if( $device_type eq 'CONNECTOR' ){
        ##############################
        # CONNECTOR DEVICE
        return 'connector device does not support set commands';

    }elsif( $device_type eq 'refrigerator' ){
        ##############################
        # REFRIGERATOR
        if( $command eq 'setRefrigerationSetpoint' ){
            $capa    = 'refrigerationSetpoint';
            $capa    = 'setpoint';
            $cmd     = 'setRefrigerationSetpoint';
            $cmdargs = [$mode];
        }elsif( $command eq 'rapidCooling' ){
            $capa    = 'rapidCooling';
            $cmd     = 'setRapidCooling';
            $cmdargs = [$mode];
        }else{
            return 'not jet implemented';
        }

    }elsif( $device_type eq 'vacuumCleaner' ){
        ##############################
        # VACUUM CLEANER
        if( $command eq 'recharge' ){
            $capa    = 'robotCleanerMovement';
            $cmd     = 'setRobotCleanerMovement';
            $cmdargs = ['homing'];
        }elsif( $command eq 'turbo' ){
            $capa    = 'robotCleanerTurboMode';
            $cmd     = 'setRobotCleanerTurboMode';
            $cmdargs = [$mode];
        }elsif( $command eq 'mode' ){
            $capa    = 'robotCleanerCleaningMode';
            $cmd     = 'setRobotCleanerCleaningMode';
            $cmdargs = [$mode];
        }

    }else{
        ##############################
        # OTHER DEVICE TYPES
        return "Device type $device_type has not jet been implemented.\nPlease consult the corresponding FHEM forum thread:\nhttps://forum.fhem.de/index.php/topic,91090.0.html\nIf you don't speak german, just phrase your issue in english, dutch or french.";

    }

    return unless $capa and $cmd;
    $data = {'commands' => [{'capability' => $capa, 'command' => $cmd, 'arguments' => $cmdargs}]};
    #$data = {'commands' => [{'capability' => 'robotCleanerTurboMode', 'command' => 'setRobotCleanerTurboMode', 'arguments' => [$mode]}]};
    #$data = {'commands' => [{'capability' => 'refrigerationSetpoint', 'command' => 'setRefrigerationSetpoint', 'arguments' => [$mode]}]};
    #$data = {'commands' => [{'capability' => 'setRefrigerationSetpoint', 'command' => $mode, 'arguments' => ['C']}]};
    #$data = {'commands' => [{'capability' => 'refrigerationSetpoint', 'command' => "setRefrigerationSetpoint($mode)", 'arguments' => []}]};
    # fuckfuckfuck, warum geht der dreck nicht :(

    my $jsoncmd = encode_utf8(encode_json($data));
my $msg = "==== command:\n$jsoncmd\n";
    Log3 $hash, 5, "SST ($device): JSON STRUCT (device set $capa):\n" . $jsoncmd;

    # push command into cloud
    my $webpost  = HTTP::Request->new('POST', 
        "https://api.smartthings.com/v1/devices/" . AttrVal($device, 'device_id', undef) . "/commands",
        ['Authorization' => "Bearer: " . AttrVal($device, 'token', undef)],
        $jsoncmd
    );
    my $webagent = LWP::UserAgent->new();
    my $jsondata = $webagent->request($webpost);

    unless( $jsondata->content){
        Log3 $hash, 3, "SST ($device): setting $capa / $cmd / $cmdargs failed";
        return "Could not set $capa for Samsung SmartThings Device $device.";
    }
    #my $jsonhash = decode_json($jsondata->content);
#Log3 $hash, 5, "SST ($device): JSON STRUCT (device set $capa):\n" . Dumper($jsonhash);
    my $jsondump = $jsondata->content;
    $jsondump =~ s/[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/g;
    Log3 $hash, 5, "SST ($device): JSON STRUCT (device set $capa reply):\n$jsondump";
$msg .= "==== reply\n$jsondump\n";

return $msg;
    SST_getDeviceStatus($hash->{NAME});
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

    <a name="token"></a>
    <li>token<br>
    This is the 32 digits hexadecimal Samsung SmartThings token. To obtain it,
    please go to <a href="https://account.smartthings.com/tokens"
    target='_blank'>https://account.smartthings.com/tokens</a>.<br>
    This attribute needs to be given on connector creation. On device
    generation it is taken from the connector settings and usually does not
    require your attention.<br>

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

    <a name="interval"></a>
    <li>interval<br>
    Für den Connector ist der Default <b>86400</b> (1 Tag).<br>
    Für die physischen Geräte ist der Default <b>300</b> (5 Minuten).<br>
    Hierbei handelt es sich um den Auffrischungszyklus in Sekunden.<br>

    <a name="IODev"></a>
    <li>IODev<br>
    Not valid for connector device.<br>
    This is usually set on define and will allow you to identify connected
    devices from the connector device. It is also used for delting all pysical
    devices when deleting the connector device.<br>
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

    <a name="token"></a>
    <li>token<br>
    This is the 32 digits hexadecimal Samsung SmartThings token. To obtain it,
    please go to <a href="https://account.smartthings.com/tokens"
    target='_blank'>https://account.smartthings.com/tokens</a>.<br>
    This attribute needs to be given on connector creation. On device
    generation it is taken from the connector settings and usually does not
    require your attention.<br>

  </ul><br>

=end html

=cut

