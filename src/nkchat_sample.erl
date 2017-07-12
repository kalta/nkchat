
-module(
nkchat_sample).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-compile([export_all]).

-define(WS, "ws://127.0.0.1:9202/api/ws").
%%-define(WS, "wss://v1.netc.io/netcomp/chat/v00/nkapi/ws").
%%-define(HTTP, "http://127.0.0.1:10201/chat").

-include_lib("nkchat.hrl").
-include_lib("nkapi/include/nkapi.hrl").

-define(SRV, sipstorm_v01).


login() ->
    nkdomain_sample:login("/ct/users/u1", "1234").



domain_find_convs() ->
    cmd(<<"objects/domain/find_all_childs">>, #{type=>?CHAT_CONVERSATION, sort=>[type, path]}).


%% f(C1), f(C2), f(C3), f(U1), f(U2), f(U3), {C1, C2, C3, U1, U2, U3} = nkchat_sample:init().
init() ->
    nkdomain:delete_all_childs(?SRV, "/ct"),
    {ok, _, Pid1} = nkdomain_sample:login(),
    C1 = <<"/ct/conversations/c1">>,
    C2 = <<"/ct/conversations/c2">>,
    C3 = <<"/ct/conversations/c3">>,
    U1 = <<"/ct/users/u1">>,
    U2 = <<"/ct/users/u2">>,
    U3 = <<"/ct/users/u3">>,
    _ = nkdomain_sample:domain_create("/", ct, ct, "ChatTest"),
    {ok, _} = nkdomain_sample:user_create("/ct", u1, s1),
    {ok, _} = nkdomain_sample:user_create("/ct", u2, s2),
    {ok, _} = nkdomain_sample:user_create("/ct", u3, s3),
    {ok, _} = conv_create("/ct", c1, "C1", private),
    {ok, _} = conv_create("/ct", c2, "C2", private),
    {ok, _} = conv_create("/ct", c3, "C3", private),
    {ok, _} = conv_add_member(C1, U1),
    {ok, _} = conv_add_member(C1, U2),
    {ok, _} = conv_add_member(C2, U1),
    {ok, _} = conv_add_member(C2, U3),
    exit(Pid1, kill),
    login(),
    timer:sleep(500),
%%    {ok, _} = session_create(),
%%    session_add_conversation(C1),
%%    session_add_conversation(C2),
    {C1, C2, C3, U1, U2, U3}.


%%conv_user_subs(UserId) ->
%%    cmd(<<"event/subscribe">>, #{class=>domain, subclass=>conversation, type=>added_to_conversation, obj_id=>UserId}).
%%
%%
%%conv_subs() ->
%%    {ok, _, UserId, _, _} = nkdomain:find(?SRV, "/chattest/users/u1"),
%%    cmd(<<"event/subscribe">>, #{class=>domain, subclass=>conversation, obj_id=>UserId}).


conv_create(Domain, Name, Desc, Class) ->
    ObjName = nkdomain_util:name(Name),
    cmd(<<"objects/conversation/create">>, #{obj_name=>ObjName, name=>Name, description=>Desc,
                                             domain_id=>Domain, conversation => #{class=>Class}}).

conv_get(Id) ->
    cmd(<<"objects/conversation/get">>, #{id=>Id}).

conv_find_member_conversations() ->
    cmd(<<"objects/conversation/find_member_conversations">>, #{}).

conv_find_member_conversations(MemberId) ->
    cmd(<<"objects/conversation/find_member_conversations">>, #{member_id=>MemberId}).

conv_find_conversations_with_members(MemberIds) ->
    cmd(<<"objects/conversation/find_conversations_with_members">>, #{member_ids=>MemberIds}).

conv_find_conversations_with_members(Domain, MemberIds) ->
    cmd(<<"objects/conversation/find_conversations_with_members">>, #{domain_id=>Domain, member_ids=>MemberIds}).

conv_add_member(Id, Member) ->
    cmd(<<"objects/conversation/add_member">>, #{id=>Id, member_id=>Member}).

conv_remove_member(Id, Member) ->
    cmd(<<"objects/conversation/remove_member">>, #{id=>Id, member_id=>Member}).

conv_delete(Id) ->
    cmd(<<"objects/conversation/delete">>, #{id=>Id}).

conv_get_last_messages(Id) ->
    cmd(<<"objects/conversation/get_last_messages">>, #{id=>Id}).

conv_get_messages(Id, Spec) ->
    cmd(<<"objects/conversation/get_messages">>, Spec#{id=>Id}).



message_create(ConvId, Msg) ->
    cmd(<<"objects/message/create">>, #{parent_id=>ConvId, ?CHAT_MESSAGE=>#{text=>Msg}}).

message_create_file(ConvId, Text, FileId) ->
    cmd(<<"objects/message/create">>, #{parent_id=>ConvId, ?CHAT_MESSAGE=>#{text=>Text, file_id=>FileId}}).

message_get(MsgId) ->
     cmd(<<"objects/message/get">>, #{id=>MsgId}).

message_update(MsgId, Msg) ->
    cmd(<<"objects/message/update">>, #{id=>MsgId, ?CHAT_MESSAGE=>#{text=>Msg}}).

message_delete(MsgId) ->
    cmd(<<"objects/message/delete">>, #{id=>MsgId}).



session_start() ->
    cmd(<<"objects/chat.session/start">>, #{}).

session_get() ->
    cmd(<<"objects/chat.session/get">>, #{}).

session_get(SessId) ->
    cmd(<<"objects/chat.session/get">>, #{id=>SessId}).

session_stop() ->
    cmd(<<"objects/chat.session/stop">>, #{}).

session_delete(Id) ->
    cmd(<<"objects/chat.session/delete">>, #{id=>Id}).

session_set_active(ConvId) ->
    cmd(<<"objects/chat.session/set_active_conversation">>, #{conversation_id=>ConvId}).

session_set_active(SessId, ConvId) ->
    cmd(<<"objects/chat.session/set_active_conversation">>, #{id=>SessId, conversation_id=>ConvId}).

session_add_conversation(ConvId) ->
    cmd(<<"objects/chat.session/add_conversation">>, #{conversation_id=>ConvId}).

session_remove_conversation(ConvId) ->
    cmd(<<"objects/chat.session/remove_conversation">>, #{conversation_id=>ConvId}).

session_get_conversations() ->
    cmd(<<"objects/chat.session/get_conversations">>, #{}).

session_get_conversation(ConvId) ->
    cmd(<<"objects/chat.session/get_conversation">>, #{conversation_id=>ConvId}).





%% ===================================================================
%% Client fun
%% ===================================================================



%% Test calling with class=test, cmd=op1, op2, data=#{nim=>1}
cmd(Cmd, Data) ->
    Pid = nkdomain_sample:get_client(),
    cmd(Pid, Cmd, Data).

cmd(Pid, Cmd, Data) ->
    nkapi_client:cmd(Pid, Cmd, Data).



%% ===================================================================
%% Http
%% ===================================================================


http_conv_get_member_conversations(SessId) ->
    http(SessId, <<"objects/conversation/get_member_conversations">>, #{}).

http(SessId, Cmd, Data) ->
    nkdomain_sample:http(SessId, Cmd, Data).
