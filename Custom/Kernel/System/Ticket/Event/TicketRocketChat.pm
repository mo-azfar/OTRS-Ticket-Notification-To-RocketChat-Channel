# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --
#Send a rockect chat notification to otrs bot in general chat channel upon ticket action. E.g: TicketQueueUpdate
#OTRS USERNAME = RC USERNAME
#
package Kernel::System::Ticket::Event::TicketRocketChat;

use strict;
use warnings;

# use ../ as lib location
use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);

use SOAP::Lite;
use Data::Dumper;
use Fcntl qw(:flock SEEK_END);
use REST::Client;
use JSON;
use LWP::UserAgent;

#yum install -y perl-LWP-Protocol-https
#yum install -y perl-JSON-MaybeXS
#cpan REST::Client
#cpan LWP::UserAgent

our @ObjectDependencies = (
    'Kernel::System::Ticket',
    'Kernel::System::Log',
	'Kernel::System::Group',
	'Kernel::System::Queue',
	'Kernel::System::User',
	
);

=head1 NAME

Kernel::System::ITSMConfigItem::Event::DoHistory - Event handler that does the history

=head1 SYNOPSIS

All event handler functions for history.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $DoHistoryObject = $Kernel::OM->Get('Kernel::System::ITSMConfigItem::Event::DoHistory');

=cut

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
  	    
		my $ticket_link = $HttpType.'://'.$FQDN.'/'.$ScriptAlias.'index.pl?Action=AgentTicketZoom;TicketID='.$TicketID;
		my $params = {
		    'username'                      => 'OTRS Bot',
		    'text'                   		=> $Message1,  ##for mention specific user, use \@username in message portion
			'channel'	=> $Channel,
			##'channel[0]'	=> '@maba',  ##for direct message to user
			##'channel[1]'	=> '@maba2', ##for direct message to user 2
			'attachments[0][title]'	=> "Ticket#$Ticket{TicketNumber}",
			'attachments[0][text]'	=> "Create : $DateTimeString\nQueue : $Ticket{Queue}\nState : $Ticket{State}",
			'attachments[1][title]'	=> 'View Ticket',
			'attachments[1][title_link]'	=> $ticket_link,
			'attachments[1][text]'	=> 'Go To The Ticket',
		  
		};
		
		my $ua = LWP::UserAgent->new;        
		#$ua->ssl_opts(verify_hostname => 0); # be tolerant to self-signed certificates
		my $response = $ua->post( $RC_URL, $params );     
		
		my $content  = $response->decoded_content();
		my $resCode = $response->code();
		my $result;
		if ($resCode eq "200")
		{
		$result="Success";
		}
		else
		{
		$result=$content;
		}
		
		## result should write to ticket history
		my $TicketHistory = $TicketObject->HistoryAdd(
        TicketID     => $TicketID,
        QueueID      => $QueueID,
        HistoryType  => 'SendAgentNotification',
        Name         => "Rocket Chat Notification to $Ticket{Queue} : $result",
        CreateUserID => 1,
		);			
	}
   
}

1;

