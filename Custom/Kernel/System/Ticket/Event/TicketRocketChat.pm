# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --
#Send ticket notification to rocket chat channel upon ticket action. E.g: TicketQueueUpdate
package Kernel::System::Ticket::Event::TicketRocketChat;

use strict;
use warnings;

# use ../ as lib location
use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);

use JSON::MaybeXS;	#yum install -y perl-JSON-MaybeXS
use LWP::UserAgent;	#yum install -y perl-LWP-Protocol-https
use HTTP::Request::Common;

our @ObjectDependencies = (
    'Kernel::System::Ticket',
    'Kernel::System::Log',
	'Kernel::System::Group',
	'Kernel::System::Queue',
	'Kernel::System::User',
	
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;
    
	#my $parameter = Dumper(\%Param);
    #$Kernel::OM->Get('Kernel::System::Log')->Log(
    #    Priority => 'error',
    #    Message  => $parameter,
    #);
	
	# check needed param
    if ( !$Param{TicketID} || !$Param{New}->{Text1} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need TicketID || Text1 (Param and Value) for this operation',
        );
        return;
    }

    #my $TicketID = $Param{Data}->{TicketID};  ##This one if using sysconfig ticket event
	my $TicketID = $Param{TicketID};  ##This one if using GenericAgent ticket event
	my $Text1 = $Param{New}->{'Text1'}; ##This one if using GenericAgent ticket event
	if ( defined $Param{New}->{'Text2'} ) { $Text1 = "$Text1<br/>$Param{New}->{Text2}"; }
	
	my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
	
	# get ticket content
	my %Ticket = $TicketObject->TicketGet(
        TicketID => $TicketID ,
		UserID        => 1,
		DynamicFields => 1,
		Extended => 0,
    );
	
	return if !%Ticket;
	
	#print "Content-type: text/plain\n\n";
	#print Dumper(\%Ticket);
	
	my $LogObject     = $Kernel::OM->Get('Kernel::System::Log');
	my $UserObject = $Kernel::OM->Get('Kernel::System::User');
	my $CustomerUserObject = $Kernel::OM->Get('Kernel::System::CustomerUser');
	my $QueueObject = $Kernel::OM->Get('Kernel::System::Queue');
	my $QueueID = $QueueObject->QueueLookup( Queue => $Ticket{Queue} );
	my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
	
	# prepare owner fullname based on Text1 tag
    if ( $Text1 =~ /<OTRS_OWNER_UserFullname>/ ) {
		my %OwnerPreferences = $UserObject->GetUserData(
        UserID        => $Ticket{OwnerID},
        NoOutOfOffice => 0,
    );
	
	for ( sort keys %OwnerPreferences ) {
        $Text1 =~ s/<OTRS_OWNER_UserFullname>/$OwnerPreferences{UserFullname}/g;
		}   
    }
	
	# prepare responsible fullname based on Text1 tag
    if ( $Text1 =~ /<OTRS_RESPONSIBLE_UserFullname>/ ) {
		my %ResponsiblePreferences = $UserObject->GetUserData(
        UserID        => $Ticket{ResponsibleID},
        NoOutOfOffice => 0,
    );
	
	for ( sort keys %ResponsiblePreferences ) {
        $Text1 =~ s/<OTRS_RESPONSIBLE_UserFullname>/$ResponsiblePreferences{UserFullname}/g;
		}   
    }
	
	# prepare customer fullname based on text1 tag
    if ( $Text1 =~ /<OTRS_CUSTOMER_UserFullname>/ ) {
		my $FullName = $CustomerUserObject->CustomerName( UserLogin => $Ticket{CustomerUserID} );
		$Text1 =~ s/<OTRS_CUSTOMER_UserFullname>/$FullName/g;
    };
	
	#change to < and > for text1 tag
	$Text1 =~ s/&lt;/</ig;
	$Text1 =~ s/&gt;/>/ig;	
	
	#get data based on text1 tag
	my $RecipientText1 = $Kernel::OM->Get('Kernel::System::Ticket::Event::NotificationEvent::Transport::Email')->_ReplaceTicketAttributes(
        Ticket => \%Ticket,
        Field  => $Text1,
    );
	
	my $HTMLUtilsObject = $Kernel::OM->Get('Kernel::System::HTMLUtils');
	#strip all html tag 
    my $Message1 = $HTMLUtilsObject->ToAscii( String => $RecipientText1 );	
	
	my $HttpType = $ConfigObject->Get('HttpType');
	my $FQDN = $ConfigObject->Get('FQDN');
	my $ScriptAlias = $ConfigObject->Get('ScriptAlias');
	
	my $DateTimeObject = $Kernel::OM->Create('Kernel::System::DateTime', ObjectParams => { String   => $Ticket{Created},});
	my $DateTimeString = $DateTimeObject->Format( Format => '%Y-%m-%d %H:%M' );
	
	my $RC_URL = $ConfigObject->Get('TicketRocketChat::Webhook');	
	my $Channel;
    my %Channels = %{ $ConfigObject->Get('TicketRocketChat::Channel') };

	for my $ChannelQueue ( sort keys %Channels )   
	{
		next if $Ticket{Queue} ne $ChannelQueue;
		$Channel = $Channels{$ChannelQueue};
        # error if queue is defined but channel name is empty
        if ( !$Channel )
        {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'notice',
                Message  => "No Channel name defined for Queue $Ticket{Queue}"
            );
            return;
        }
  	    
		my $TicketURL = $HttpType.'://'.$FQDN.'/'.$ScriptAlias.'index.pl?Action=AgentTicketPrint;TicketID='.$TicketID;

		# For Asynchronous sending
		my $TaskName = substr "Recipient".rand().$Channel, 0, 255;
		
		# instead of direct sending, we use task scheduler
		my $TaskID = $Kernel::OM->Get('Kernel::System::Scheduler')->TaskAdd(
			Type                     => 'AsynchronousExecutor',
			Name                     => $TaskName,
			Attempts                 =>  1,
			MaximumParallelInstances =>  0,
			Data                     => 
			{
				Object   => 'Kernel::System::Ticket::Event::TicketRocketChat',
				Function => 'SendMessageRCChannel',
				Params   => 
						{
							Channel	=>	$Channel,
							RCURL	=>	$RC_URL,
							TicketURL	=>	$TicketURL,
							TicketNumber	=>	$Ticket{TicketNumber},
							Message	=>	$Message1,
							Created	=> $DateTimeString,
							Queue	=> $Ticket{Queue},
							State	=>	$Ticket{State},	
							TicketID      => $TicketID, #sent for log purpose
						},
			},
		);
		
	}
   
}

=cut

		my $Test = $Self->SendMessageRC(
					Channel	=>	$Channel,
					RCURL	=>	$RC_URL,
					TicketURL	=>	$TicketURL,
					TicketNumber	=>	$Ticket{TicketNumber},
					Message	=>	$Message1,
					Created	=> $DateTimeString,
					Queue	=> $Ticket{Queue},
					State	=>	$Ticket{State},	
					TicketID      => $TicketID, #sent for log purpose
		);

=cut

sub SendMessageRCChannel {
	my ( $Self, %Param ) = @_;

	# check for needed stuff
    for my $Needed (qw(Channel RCURL TicketURL TicketNumber Message Created Queue State TicketID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Missing parameter $Needed!",
            );
            return;
        }
    }
	
	my $ua = LWP::UserAgent->new;
	utf8::decode($Param{Message});
	
	my $params = {
	'username'   => 'OTRS Bot',
	'text'      => $Param{Message},  ##for mention specific user, use \@username in message portion
	'channel'	=> $Param{Channel},
	##'channel[0]'	=> '@maba',  ##for direct message to user
	##'channel[1]'	=> '@maba2', ##for direct message to user 2
	'attachments[0][title]'	=> "Ticket#$Param{TicketNumber}",
	'attachments[0][text]'	=> "Create : $Param{Created}\nQueue : $Param{Queue}\nState : $Param{State}",
	'attachments[1][title]'	=> 'View Ticket',
	'attachments[1][title_link]'	=> $Param{TicketURL},
	'attachments[1][text]'	=> 'Go To The Ticket',	  
	};
	
	#$ua->ssl_opts(verify_hostname => 0); # be tolerant to self-signed certificates
	my $response = $ua->post( $Param{RCURL}, $params );
	
	my $content  = $response->decoded_content();
	my $resCode =$response->code();
	
	if ($resCode ne 200)
	{
	$Kernel::OM->Get('Kernel::System::Log')->Log(
			 Priority => 'error',
			 Message  => "RocketChat notification for Queue $Param{Queue}: $resCode $content",
		);
	}
	else
	{
	my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
	my $TicketHistory = $TicketObject->HistoryAdd(
        TicketID     => $Param{TicketID},
        HistoryType  => 'SendAgentNotification',
        Name         => "Sent RocketChat Notification for Queue $Param{Queue}",
        CreateUserID => 1,
		);			
	}
}

1;

