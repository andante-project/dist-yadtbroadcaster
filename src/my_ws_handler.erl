%% @private
-module(my_ws_handler).
-behaviour(cowboy_websocket_handler).

-export([init/3]).
-export([websocket_init/3]).
-export([websocket_handle/3]).
-export([websocket_info/3]).
-export([websocket_terminate/3]).


-define(SUBPROTHEADER,<<"sec-websocket-protocol">>).
-define(WSMSGPACK,<<"wamp.2.msgpack">>).
-define(WSJSON,<<"wamp.2.json">>).
-define(WSMSGPACK_BATCHED,<<"wamp.2.msgpack.batched">>).
-define(WSJSON_BATCHED,<<"wamp.2.json.batched">>).

-record(state,{
          enc = undefined,
          router = undefined,
          buffer = <<"">>
         }).

init({Transport, http}, _Req, _Opts) when Transport == tcp; Transport == ssl ->
    {upgrade, protocol, cowboy_websocket}.

websocket_init(_TransportName, Req, _Opts) ->
    % need to check for the wamp.2.json or wamp.2.msgpack
    {ok, Protocols, Req1} = cowboy_req:parse_header(?SUBPROTHEADER, Req),
    case lists:nth(1,Protocols) of
        ?WSMSGPACK ->
            Req2  = cowboy_req:set_resp_header(?SUBPROTHEADER,?WSMSGPACK,Req1),
            {ok,Req2,#state{enc=msgpack}};
        ?WSMSGPACK_BATCHED ->
            Req2  = cowboy_req:set_resp_header(?SUBPROTHEADER,?WSMSGPACK_BATCHED,Req1),
            {ok,Req2,#state{enc=msgpack_batched}};
        ?WSJSON ->
            Req2  = cowboy_req:set_resp_header(?SUBPROTHEADER,?WSJSON,Req1),
            {ok,Req2,#state{enc=json}};
        ?WSJSON_BATCHED ->
            Req2  = cowboy_req:set_resp_header(?SUBPROTHEADER,?WSJSON_BATCHED,Req1),
            {ok,Req2,#state{enc=json_batched}};
        _ ->
            {shutdown,Req1}
    end.


websocket_handle({text, Data}, Req, #state{enc=json}=State) ->
    {ok,NewState} = handle_wamp(Data,State),
    {ok,Req,NewState};
websocket_handle({binary, Data}, Req, #state{enc=msgpack}=State) ->
    {ok,NewState} = handle_wamp(Data,State),
    {ok,Req,NewState};
websocket_handle(_Data, Req, State) ->
    {ok, Req, State}.

websocket_info({erwa,shutdown}, Req, State) ->
    {shutdown,Req,State};
websocket_info({erwa,Msg}, Req, #state{enc=Enc}=State) when is_tuple(Msg)->
    Rpl = erwa_protocol:serialize(Msg,Enc),
    Reply =
    case Enc of
        json -> {text,Rpl};
        msgpack -> {binary,Rpl}
    end,
    {reply,Reply,Req,State};
websocket_info(_Data, Req, State) ->
    {ok,Req,State}.

websocket_terminate(_Reason, _Req, _State) ->
    ok.


forward_to_others(_, []) ->
    ok;
forward_to_others(Messages, [H|T]) ->
    forward_to_other(Messages, H),
    forward_to_others(Messages, T).

forward_to_other(Messages, Node) ->
    io:format("forwarding messages to ~p~n", [Node]),
    {forwards, Node} ! {self(), Messages}.

handle_wamp(Data,#state{buffer=Buffer, enc=Enc, router=Router}=State) ->
    {Messages,NewBuffer} = erwa_protocol:deserialize(<<Buffer/binary, Data/binary>>,Enc),
    io:format("~p~n", [Messages]),
    ok = forward_to_others(Messages, nodes()),
    {ok,NewRouter} = erwa_protocol:forward_messages(Messages,Router),
    {ok,State#state{router=NewRouter,buffer=NewBuffer}}.


-ifdef(TEST).




-endif.