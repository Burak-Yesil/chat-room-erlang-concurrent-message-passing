%%Burak Yesil and Thomas Lapinta
%%I pledge my honor that I have abided by the Stevens Honor System.


-module(server).

-export([start_server/0]).

-include_lib("./defs.hrl").

-spec start_server() -> _.
-spec loop(_State) -> _.
-spec do_join(_ChatName, _ClientPID, _Ref, _State) -> _.
-spec do_leave(_ChatName, _ClientPID, _Ref, _State) -> _.
-spec do_new_nick(_State, _Ref, _ClientPID, _NewNick) -> _.
-spec do_client_quit(_State, _Ref, _ClientPID) -> _NewState.

start_server() ->
    catch(unregister(server)),
    register(server, self()),
    case whereis(testsuite) of
	undefined -> ok;
	TestSuitePID -> TestSuitePID!{server_up, self()}
    end,
    loop(
      #serv_st{
	 nicks = maps:new(), %% nickname map. client_pid => "nickname"
	 registrations = maps:new(), %% registration map. "chat_name" => [client_pids]
	 chatrooms = maps:new() %% chatroom map. "chat_name" => chat_pid
	}
     ).

loop(State) ->
    receive 
	%% initial connection
	{ClientPID, connect, ClientNick} ->
	    NewState =
		#serv_st{
		   nicks = maps:put(ClientPID, ClientNick, State#serv_st.nicks),
		   registrations = State#serv_st.registrations,
		   chatrooms = State#serv_st.chatrooms
		  },
	    loop(NewState);
	%% client requests to join a chat
	{ClientPID, Ref, join, ChatName} ->
	    NewState = do_join(ChatName, ClientPID, Ref, State),
	    loop(NewState);
	%% client requests to join a chat
	{ClientPID, Ref, leave, ChatName} ->
	    NewState = do_leave(ChatName, ClientPID, Ref, State),
	    loop(NewState);
	%% client requests to register a new nickname
	{ClientPID, Ref, nick, NewNick} ->
	    NewState = do_new_nick(State, Ref, ClientPID, NewNick),
	    loop(NewState);
	%% client requests to quit
	{ClientPID, Ref, quit} ->
	    NewState = do_client_quit(State, Ref, ClientPID),
	    loop(NewState);
	{TEST_PID, get_state} ->
	    TEST_PID!{get_state, State},
	    loop(State)
    end.

%% executes join protocol from server perspective
do_join(ChatName, ClientPID, Ref, State) ->
	Check = maps:find(ChatName, State#serv_st.chatrooms),
	if 
		Check == error ->
			ChatPID = spawn(chatroom, start_chatroom, [ChatName]),
			ClientNick= maps:get(ClientPID, State#serv_st.nicks),
			ChatPID!{self(), Ref, register, ClientPID, ClientNick},
			#serv_st{
						nicks = State#serv_st.nicks,
						registrations = maps:put(ChatName, [ClientPID], State#serv_st.registrations),
						chatrooms = maps:put(ChatName, ChatPID, State#serv_st.chatrooms)
			};
		true ->
			ChatPID = maps:get(ChatName, State#serv_st.chatrooms),
			ClientNick= maps:get(ClientPID, State#serv_st.nicks),
			ChatPID!{self(), Ref, register, ClientPID, ClientNick},
			#serv_st{
						nicks = State#serv_st.nicks,
						registrations = maps:put(ChatName, lists:append([ClientPID], maps:get(ChatName, State#serv_st.registrations)), State#serv_st.registrations),
						chatrooms = State#serv_st.chatrooms
			}
	end.

%% executes leave protocol from server perspective
do_leave(ChatName, ClientPID, Ref, State) ->
	ChatPID = maps:get(ChatName, State#serv_st.chatrooms),
    PIDList = maps:get(ChatName, State#serv_st.registrations),
	UpdatedList = lists:delete(ClientPID, PIDList),
	ReturnState = #serv_st{
		nicks = State#serv_st.nicks,
		registrations = maps:put(ChatName, UpdatedList, State#serv_st.registrations),
		chatrooms = State#serv_st.chatrooms
	},
	ChatPID!{self(), Ref, unregister, ClientPID},
	ClientPID!{self(), Ref, ack_leave},
	ReturnState.
	

%% executes new nickname protocol from server perspective
do_new_nick(State, Ref, ClientPID, NewNick) ->
	AllNicks = maps:values(State#serv_st.nicks),
	Check = lists:member(NewNick, AllNicks),
	if
		
		Check == true -> 
			ClientPID!{self(), Ref, err_nick_used};
		true ->
			ChatroomsWithUser = maps:keys(maps:filter(fun(_X,Y) -> lists:member(ClientPID, Y) end, State#serv_st.registrations)),
			lists:foreach(fun(X) -> 
									Temp = maps:get(X, State#serv_st.chatrooms),
									Temp!{self(), Ref, update_nick, ClientPID, NewNick} end, ChatroomsWithUser),
			ClientPID!{self(), Ref, ok_nick},

			#serv_st{
				nicks = maps:put(ClientPID, NewNick, State#serv_st.nicks),
				registrations = State#serv_st.registrations,
				chatrooms = State#serv_st.chatrooms
			}
			
	end.

% fitler through the map regis lambda checks if pid is in value of key value pair 

%% executes client quit protocol from server perspective
do_client_quit(State, Ref, ClientPID) ->
	ChatroomsWithUser = maps:keys(maps:filter(fun(_X,Y) -> lists:member(ClientPID, Y) end, State#serv_st.registrations)),
	lists:foreach(fun(X) -> 
									Temp = maps:get(X, State#serv_st.chatrooms),
									Temp!{self(), Ref, unregister, ClientPID} end, ChatroomsWithUser),
	ClientPID!{self(), Ref, ack_quit},
	#serv_st{
		nicks = maps:remove(ClientPID, State#serv_st.nicks),
		registrations = maps:map(fun(_X, Y) ->
											Check = lists:member(ClientPID, Y),
											if
												Check == true -> lists:delete(ClientPID, Y);
												true -> Y
											end
										end, State#serv_st.registrations),
			chatrooms = State#serv_st.chatrooms
	}.
    

