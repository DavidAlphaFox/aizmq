%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at http://mozilla.org/MPL/2.0/.

%% @doc ZeroMQ Pull Pattern for Erlang
%%
%% This pattern implement Pull especification
%% from: http://rfc.zeromq.org/spec:30/PIPELINE#toc4

-module(chumak_pull).
-behaviour(chumak_pattern).

-export([valid_peer_type/1, init/1, peer_flags/1, accept_peer/2, peer_ready/3,
         send/3, recv/2,
         send_multipart/3, recv_multipart/2, peer_recv_message/3,
         queue_ready/3, peer_disconected/2, identity/1
        ]).

-record(chumak_pull, {
          identity               :: string(),
          pending_recv           :: nil | {from, From::term()},
          pending_recv_multipart :: nil | {from, From::term()},
          recv_queue             :: queue:queue()
         }).

valid_peer_type(push)    -> valid;
valid_peer_type(_)      -> invalid.

init(Identity) ->
    State = #chumak_pull{
               identity=Identity,
               recv_queue=queue:new(),
               pending_recv=nil,
               pending_recv_multipart=nil
              },
    {ok, State}.

identity(#chumak_pull{identity=Identity}) -> Identity.

peer_flags(_State) ->
    {pull, [incoming_queue]}.

accept_peer(State, PeerPid) ->
    {reply, {ok, PeerPid}, State}.

peer_ready(State, _PeerPid, _Identity) ->
    {noreply, State}.

send(State, Data, From) ->
    send_multipart(State, [Data], From).

recv(#chumak_pull{pending_recv=nil, pending_recv_multipart=nil}=State, From) ->
    case queue:out(State#chumak_pull.recv_queue) of
        {{value, Multipart}, NewRecvQueue} ->
            Msg = binary:list_to_bin(Multipart),
            {reply, {ok, Msg}, State#chumak_pull{recv_queue=NewRecvQueue}};
        {empty, _RecvQueue} ->
            {noreply, State#chumak_pull{pending_recv={from, From}}}
    end;

recv(State, _From) ->
    {reply, {error, already_pending_recv}, State}.

send_multipart(State, _Multipart, _From) ->
    {reply, {error, not_use}, State}.

recv_multipart(#chumak_pull{pending_recv=nil, pending_recv_multipart=nil}=State, From) ->
    case queue:out(State#chumak_pull.recv_queue) of
        {{value, Multipart}, NewRecvQueue} ->
            {reply, {ok, Multipart}, State#chumak_pull{recv_queue=NewRecvQueue}};

        {empty, _RecvQueue} ->
            {noreply, State#chumak_pull{pending_recv_multipart={from, From}}}
    end;

recv_multipart(State, _From) ->
    {reply, {error, already_pending_recv}, State}.

peer_recv_message(State, _Message, _From) ->
    %% This function will never called, because use incoming_queue property
    {noreply, State}.

queue_ready(#chumak_pull{pending_recv=nil, pending_recv_multipart=nil}=State, _Identity, PeerPid) ->
    {out, Multipart} = chumak_peer:incoming_queue_out(PeerPid),
    NewRecvQueue = queue:in(Multipart, State#chumak_pull.recv_queue),
    {noreply, State#chumak_pull{recv_queue=NewRecvQueue}};

%% when pending recv
queue_ready(#chumak_pull{pending_recv={from, PendingRecv}, pending_recv_multipart=nil}=State, _Identity, PeerPid) ->
    {out, Multipart} = chumak_peer:incoming_queue_out(PeerPid),
    Msg = binary:list_to_bin(Multipart),
    gen_server:reply(PendingRecv, {ok, Msg}),
    {noreply, State#chumak_pull{pending_recv=nil}};

%% when pending recv_multipart
queue_ready(#chumak_pull{pending_recv=nil, pending_recv_multipart={from, PendingRecv}}=State, _Identity, PeerPid) ->
    {out, Multipart} = chumak_peer:incoming_queue_out(PeerPid),
    gen_server:reply(PendingRecv, {ok, Multipart}),
    {noreply, State#chumak_pull{pending_recv_multipart=nil}}.

peer_disconected(State, _PeerPid) ->
    {noreply, State}.
