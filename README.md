# OTRS-Ticket-Notification-To-RocketChat-Channel
- Built for OTRS CE v6.0.x  
- Send a ticket notifictaion to Rocket Chat channel upon ticket action. E.g: TicketQueueUpdate

		Used CPAN Module:
		
		JSON::MaybeXS; #yum install -y perl-JSON-MaybeXS
		LWP::UserAgent;  #yum install -y perl-LWP-Protocol-https
		HTTP::Request::Common;	 


1. RC must be configured to accept incoming webhook.  
Administration -> Integration -> New integration -> Incoming WebHook  

		- Enabled: True  
		- Name: OTRS Notification  
		- Post to channel: #helpdesk  
		- Post as: rocket.cat  
		- Alias: OTRS Bot


Then, submit/save. Open back this webhook, take note on the 'Webhook URL'

		#bot maybe also need to have permission in mention here and mention all


2. Update the RocketChat Webhook URL at System Configuration > TicketRocketChat::Webhook  
  
3. Update the RocketChat Queue->Channel in System Configuration >TicketRocketChat::Channel  

		Queue 1 Name => RocketChat channel  
		
		Example:
		Helpdesk => #helpdesk  
		an so on..
		
  		
4. Admin must create a new Generic Agent (GA) with option to execute custom module.

		[Mandatory][Name]: Up to you.
		[Mandatory][Event Based Execution] : Mandatory. Up to you. Example, TicketQueueUpdate for moving ticket to another queue
		[Optional][Select Ticket]: Optional. Up to you.
		[Mandatory][Execute Custom Module] : Module => Kernel::System::Ticket::Event::TicketRocketChat
	
		[Mandatory][Param 1 Key] : Text1  
		[Mandatory][Param 1 Value] : Text to be sent to the channel.
		[Optional][Param 2 Key] : Text2  
		[Optional][Param 2 Value] : Additional text to be sent to the channel.

		#Support OTRS ticket TAG only. bold, newline must be in HTML code.  
		#Support <OTRS_NOTIFICATION_RECIPIENT_UserFullname>, <OTRS_OWNER_UserFullname>, <OTRS_RESPONSIBLE_UserFullname> and <OTRS_CUSTOMER_UserFullname> tag.


[![rc.png](https://i.postimg.cc/SRRHcKVK/rc.png)](https://postimg.cc/ctqDS0pq)
