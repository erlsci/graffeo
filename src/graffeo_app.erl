%%%-------------------------------------------------------------------
%% @doc graffeo public API
%% @end
%%%-------------------------------------------------------------------

-module(graffeo_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    graffeo_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
