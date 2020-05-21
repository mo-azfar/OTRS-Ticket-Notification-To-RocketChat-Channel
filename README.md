# OTRS-Ticket-Notification-To-RocketChat-Channel
- Built for OTRS CE v6.0.x  
- Send a ticket notification to Rocket Chat channel upon ticket action. E.g: TicketQueueUpdate
- **Require CustomMessage API**  

1. RC must be configured to accept incoming webhook.  
Administration -> Integration -> New integration -> Incoming WebHook

- Enabled: True  
- Name: OTRS Notification  
- Post to channel: #helpdesk  
- Post as: rocket.cat  
- Alias: OTRS Bot

Then, submit/save. Open back this webhook, take note on the 'Webhook URL'

#bot also need to have permission in mention here and mention all


2. Update the RocketChat Webhook URL at System Configuration > TicketRocketChat::Webhook

3. Update the RocketChat Queue->Channel in System Configuration >TicketRocketChat::Channel

Queue 1 Name => RocketChat channel  
Helpdesk => #helpdesk  
an so on..

4. Admin must create a new Generic Agent (GA) with option to execute custom module.

Execute Custom Module => Module => Kernel::System::Ticket::Event::TicketRocketChat
	
[MANDATORY PARAM]
	
Param 1 Key => Text1  
Param 1 Value => *Text to be sent to the user.  
#Also support OTRS ticket TAG only.  
#Also support <OTRS_NOTIFICATION_RECIPIENT_UserFullname>, <OTRS_OWNER_UserFullname>, <OTRS_RESPONSIBLE_UserFullname> and <OTRS_CUSTOMER_UserFullname> tag.
	
[OPTINAL PARAM]
	
Param 2 Key => Text2  
Param 2 Value => *Additional text to be sent to the user.  
#Also support OTRS ticket TAG only. 
#Also support <OTRS_NOTIFICATION_RECIPIENT_UserFullname>, <OTRS_OWNER_UserFullname>, <OTRS_RESPONSIBLE_UserFullname> and <OTRS_CUSTOMER_UserFullname> tag.

[![rc.png](https://i.postimg.cc/SRRHcKVK/rc.png)](https://postimg.cc/ctqDS0pq)
