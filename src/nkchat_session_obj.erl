%% -------------------------------------------------------------------
%%
%% Copyright (c) 2016 Carlos Gonzalez Florido.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

%% @doc Session Object
-module(nkchat_session_obj).
-behavior(nkdomain_obj).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([create/2, find/2, start/3, stop/2, get_info/2]).
-export([set_active_conversation/3, set_last_message/5, add_conversation/3, remove_conversation/3]).
-export([conversation_msg/3]).
-export([object_get_info/0, object_mapping/0, object_syntax/1,
         object_api_syntax/3, object_api_allow/4, object_api_cmd/4]).
-export([object_start/1, object_save/1, object_sync_op/3, object_async_op/2, object_handle_info/2]).
-export([find_unread/2]).

-include("nkchat.hrl").
-include_lib("nkdomain/include/nkdomain.hrl").
-include_lib("nkdomain/include/nkdomain_debug.hrl").


%% Period to find for inactive conversations
-define(CHECK_TIME, 5*60*1000).


%% ===================================================================
%% Public
%% ===================================================================

%% @doc
create(Srv, User) ->
    case nkdomain_obj_lib:find(Srv, User) of
        #obj_id_ext{obj_id = UserId} ->
            Opts = #{
                type_obj => #{conversations => []}
            },
            nkdomain_obj_lib:make_and_create(Srv, UserId, ?CHAT_SESSION, Opts);
        _ ->
            {error, user_not_found}
    end.


%% @doc Tries to find a previous session for this user
-spec find(nkservice:id(), nkdomain:id()) ->
    {ok, nkdomain:obj_id()} | {error, term()}.

find(Srv, User) ->
    case nkdomain_obj_lib:find(Srv, User) of
        #obj_id_ext{obj_id=UserId} ->
            Search = #{
                filters => #{
                    type => ?CHAT_SESSION,
                    parent_id => UserId
                },
                sort => [#{created_time => #{order => desc}}]
            },
            case nkdomain_store:find(Srv, Search) of
                {ok, _, [], _Meta} ->
                    {error, session_not_found};
                {ok, _, [#{<<"obj_id">>:=ObjId}|_], _Meta} ->
                    {ok, ObjId};
                {error, Error} ->
                    {error, Error}
            end;
        _ ->
            {error, user_not_found}
    end.


%% @doc Starts a new session, connected to the Caller
start(Srv, Id, CallerPid) ->
    case nkdomain_obj_lib:load(Srv, Id, #{register=>{?MODULE, CallerPid}}) of
        #obj_id_ext{pid=Pid} ->
            nkdomain_obj:sync_op(Pid, {?MODULE, get_conversations});
        {error, Error} ->
            {error, Error}
    end.


%% @doc
stop(Srv, Id) ->
    nkdomain_obj_lib:unload(Srv, Id, user_stop, session_not_found).


%% @doc
add_conversation(Srv, Id, ConvId) ->
    case nkdomain_obj_lib:find(Srv, ConvId) of
        #obj_id_ext{type = ?CHAT_CONVERSATION, obj_id=ConvId2} ->
            sync_op(Srv, Id, {?MODULE, add_conv, ConvId2});
        #obj_id_ext{} ->
            {error, conversation_not_found};
        {error, object_not_found} ->
            {error, conversation_not_found};
        {error, Error} ->
            {error, Error}
    end.

%% @doc
remove_conversation(Srv, Id, ConvId) ->
    sync_op(Srv, Id, {?MODULE, rm_conv, ConvId}).


%% @doc
get_info(Srv, Id) ->
    sync_op(Srv, Id, {?MODULE, get_conversations}).


%% @doc
set_active_conversation(Srv, Id, ConvId) ->
    sync_op(Srv, Id, {?MODULE, set_active_conv, ConvId}).


%% @doc
set_last_message(Srv, Id, ConvId, MsgId, Time) ->
    async_op(Srv, Id, {?MODULE, set_last_msg, ConvId, MsgId, Time}).


%% @doc
conversation_msg(Pid, ConvId, Msg) ->
    nkdomain_obj:async_op(Pid, {conversation_msg, ConvId, Msg}).



%% ===================================================================
%% nkdomain_obj behaviour
%% ===================================================================


-record(?MODULE, {
    monitor :: nkdomain_monitor:monitor(),
    active :: undefined | nkdomain:obj_id(),
    unread = #{} :: #{ConvId::nkdomain:obj_id() => integer()},
    meta = #{} :: map()
}).



%% @private
object_get_info() ->
    #{
        type => ?CHAT_SESSION
    }.


%% @private
object_mapping() ->
    #{
        conversations => #{
            type => object,
            dynamic => false,
            properties => #{
                obj_id => #{type => keyword},
                last_active_time => #{type => date},
                last_read_message_id => #{type => keyword},
                last_read_message_time => #{type => date}
            }
        }
    }.


%% @private
object_syntax(_) ->
    #{
        conversations =>
            {list,
                {syntax, #{
                    obj_id => binary,
                    last_active_time => integer,
                    last_read_message_id => binary,
                    last_read_message_time => integer,
                    '__mandatory' => [
                        <<?CHAT_SESSION/binary, ".conversations.obj_id">>,
                        <<?CHAT_SESSION/binary, ".conversations.last_active_time">>,
                        <<?CHAT_SESSION/binary, ".conversations.last_read_message_id">>,
                        <<?CHAT_SESSION/binary, ".conversations.last_read_message_time">>
                    ]
                }}}
    }.


%% @private
object_api_syntax(Sub, Cmd, Syntax) ->
    nkchat_session_obj_syntax:api(Sub, Cmd, Syntax).


%% @private
object_api_allow(_Sub, _Cmd, _Data, State) ->
    {true, State}.


%% @private
object_api_cmd(Sub, Cmd, Data, State) ->
    nkchat_session_obj_api:cmd(Sub, Cmd, Data, State).


%% @private When the object is loaded, we make our cache
object_start(#obj_session{srv_id=SrvId, obj=Obj, parent_id=UserId}=Session) ->
    #{?CHAT_SESSION := #{conversations:=Convs}} = Obj,
    Monitor = lists:foldl(
        fun(#{obj_id:=ConvId}=Conv, Acc) ->
            case nkdomain_monitor:load_obj(ConvId, Conv, Acc) of
                {enabled, Acc2} ->
                    Acc2;
                {disabled, Acc2} ->
                    ?LLOG(notice, "could not active conversation ~s", [ConvId], Session),
                    Acc2;
                {error, Error} ->
                    ?LLOG(notice, "could not load conversation ~s: ~p", [ConvId, Error], Session),
                    Acc
            end
        end,
        nkdomain_monitor:new(SrvId, {?MODULE, UserId}),
        Convs),
    self() ! {?MODULE, check_time},
    Data = #?MODULE{
        monitor = Monitor
    },
    {ok, Session#obj_session{data=Data}}.


%% @private Prepare the object for saving
object_save(#obj_session{obj=Obj}=Session) ->
    Monitor = get_monitor(Session),
    Convs = [O || {_Enabled, O} <- nkdomain_monitor:get_obj_values(Monitor)],
    ChatObj = #{conversations => Convs},
    Obj2 = ?ADD_TO_OBJ(?CHAT_SESSION, ChatObj, Obj),
    {ok, Session#obj_session{obj=Obj2}};

object_save(Session) ->
    {ok, Session}.


%% @private
object_sync_op({?MODULE, get_conversations}, _From, #obj_session{obj_id=ObjId}=Session) ->
    Monitor = get_monitor(Session),
    Convs = lists:map(
        fun
            ({enabled, Obj}) -> Obj#{enabled=>true};
            ({disabled, Obj}) -> Obj#{enabled=>false}
        end,
        nkdomain_monitor:get_obj_values(Monitor)),
    {reply, {ok, ObjId, #{conversations=>Convs}}, Session};

object_sync_op({?MODULE, set_active_conv, ConvId}, _From, Session) ->
    Monitor = get_monitor(Session),
    case nkdomain_monitor:get_obj(ConvId, Monitor) of
        {enabled, Conv, _Pid} ->
            ?DEBUG("activated conversation ~s", [ConvId], Session),
            Conv2 = Conv#{
                last_active_time => nklib_util:m_timestamp()
            },
            {ok, Monitor2} = nkdomain_monitor:update_obj(ConvId, Conv2, Monitor),
            Session2 = update_active(ConvId, Monitor2, Session),
            {reply_and_save, ok, Session2};
        {disabled, _, _} ->
            {reply, {error, conversation_is_disabled}, Session};
        not_found ->
            {reply, {error, conversation_not_found}, Session}
    end;

object_sync_op({?MODULE, add_conv, ConvId}, _From, Session) ->
    Monitor = get_monitor(Session),
    Conv = #{
        obj_id => ConvId,
        last_active_time => 0,
        last_read_message_id => <<>>,
        last_read_message_time => 0
    },
    case nkdomain_monitor:add_obj(ConvId, Conv, Monitor) of
        {ok, _, Monitor2} ->
            Session2 = update_monitor(Monitor2, Session),
            ?DEBUG("added conversation ~s", [ConvId], Session),
            {reply_and_save, {ok, ConvId}, Session2};
        {error, object_not_found} ->
            {reply, {error, conversation_not_found}, Session};
        {error, Error} ->
            {reply, {error, Error}, Session}
    end;

object_sync_op({?MODULE, rm_conv, ConvId}, _From, Session) ->
    Monitor = get_monitor(Session),
    case nkdomain_monitor:rm_obj(ConvId, Monitor) of
        {ok, Monitor2} ->
            Session2 = update_monitor(Monitor2, Session),
            ?DEBUG("removed conversation ~s", [ConvId], Session),
            {reply_and_save, ok, Session2};
        {error, object_not_found} ->
            {reply, {error, conversation_not_found}, Session};
        {error, Error} ->
            {reply, {error, Error}, Session}
    end;

object_sync_op(_Op, _From, _Session) ->
    continue.


%% @private
object_async_op({?MODULE, set_last_msg, ConvId, MsgId, Time}, Session) ->
    Monitor = get_monitor(Session),
    case nkdomain_monitor:get_obj(ConvId, Monitor) of
        {enabled, Conv, _Pid} ->
            Conv2 = Conv#{
                last_read_message_id => MsgId,
                last_read_message_time => Time
            },
            {ok, Monitor2} = nkdomain_monitor:update_obj(ConvId, Conv2, Monitor),
            Session2 = update_monitor( Monitor2, Session),
            ?DEBUG("set last message for conversation ~s", [ConvId], Session),
            {noreply, Session2};
        not_found ->
            {noreply, Session}
    end;

object_async_op(_Op, _Session) ->
    continue.


%% @private
object_handle_info({?MODULE, check_time}, Session) ->
    Monitor = get_monitor(Session),
    Session2 = case nkdomain_monitor:reload_disabled(Monitor) of
        {[], _} ->
            Session;
        {ObjIds, Monitor2} ->
            ?LLOG(notice, "reloaded objects ~p", [ObjIds], Session),
            update_monitor(Monitor2, Session)
    end,
    erlang:send_after(?CHECK_TIME, self(), {?MODULE, check_time}),
    {noreply, Session2};

object_handle_info({'DOWN', _Ref, process, Pid, _Reason}, Session) ->
    Monitor1 = get_monitor(Session),
    case nkdomain_monitor:down_obj(Pid, Monitor1) of
        {ok, ObjId, _Obj, Monitor2} ->
            ?LLOG(notice, "member ~s is disabled", [ObjId], Session),
            {noreply, update_monitor(Monitor2, Session)};
        not_found ->
            continue
    end;

object_handle_info(_Info, _Session) ->
    continue.


%% ===================================================================
%% Internal
%% ===================================================================

%% @private
sync_op(Srv, Id, Op) ->
    nkdomain_obj_lib:sync_op(Srv, Id, ?CHAT_SESSION, Op, session_not_found).


%% @private
async_op(Srv, Id, Op) ->
    nkdomain_obj_lib:async_op(Srv, Id, ?CHAT_SESSION, Op, session_not_found).


%% @private
get_monitor(#obj_session{data=SessData}) ->
    #?MODULE{monitor=Monitor} = SessData,
    Monitor.


%% @private
update_active(ConvId, Monitor, #obj_session{data=SessData}=Session) ->
    SessData2 = SessData#?MODULE{monitor=Monitor, active=ConvId},
    Session#obj_session{data=SessData2, is_dirty=true}.


%% @private
update_monitor(Monitor, #obj_session{data=SessData}=Session) ->
    SessData2 = SessData#?MODULE{monitor=Monitor},
    Session#obj_session{data=SessData2, is_dirty=tue}.


find_unread(Conv, #{srv_id:=SrvId}) ->
    #{obj_id:=ConvId, last_read_message_id:=_MsgId, last_read_message_time:=Time} = Conv,
    Search = #{
        filters => #{
            type => ?CHAT_MESSAGE,
            parent_id => ConvId,
            created_time => {Time, none}
        },
        size => 0
    },
    nkdomain_store:find(SrvId, Search).


