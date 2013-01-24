-module(cs347_regression_test).

-include_lib("xmerl/include/xmerl.hrl").

%% @doc Regression test for `riak_cs' <a href="https://github.com/basho/riak_cs/issues/347">
%% issue 347</a>. The issue description is: No response body in 404 to the
%% bucket that have never been created once.

-export([confirm/0]).
-include_lib("eunit/include/eunit.hrl").

-define(TEST_BUCKET, "riak_test_bucket").

confirm() ->
    {RiakNodes, _CSNodes, _Stanchion} = rtcs:setup(4),

    FirstNode = hd(RiakNodes),

    {AccessKeyId, SecretAccessKey} = rtcs:create_user(FirstNode, 1),

    %% User config
    UserConfig = rtcs:config(AccessKeyId, SecretAccessKey, rtcs:cs_port(FirstNode)),

    lager:info("User is valid on the cluster, and has no buckets"),
    ?assertEqual([{buckets, []}], erlcloud_s3:list_buckets(UserConfig)),

    ListObjectRes1 =
        case catch erlcloud_s3:list_objects(?TEST_BUCKET, UserConfig) of
            {'EXIT', {{aws_error, Error}, _}} ->
                Error;
            Result ->
                Result
        end,
    ?assert(verify_error_response(ListObjectRes1)),

    lager:info("creating bucket ~p", [?TEST_BUCKET]),
    ?assertEqual(ok, erlcloud_s3:create_bucket(?TEST_BUCKET, UserConfig)),

    ?assertMatch([{buckets, [[{name, ?TEST_BUCKET}, _]]}],
        erlcloud_s3:list_buckets(UserConfig)),

    lager:info("deleting bucket ~p", [?TEST_BUCKET]),
    ?assertEqual(ok, erlcloud_s3:delete_bucket(?TEST_BUCKET, UserConfig)),

    ListObjectRes2 =
        case catch erlcloud_s3:list_objects(?TEST_BUCKET, UserConfig) of
            {'EXIT', {{aws_error, Error2}, _}} ->
                Error2;
            Result2 ->
                Result2
        end,
    ?assert(verify_error_response(ListObjectRes2)),
    pass.

verify_error_response({_, 404, _, RespStr}) ->
    {RespXml, _} = xmerl_scan:string(RespStr),
    lists:foldl(fun process_error_content/2, true, RespXml#xmlElement.content);
verify_error_response({_, _, _, _}) ->
    false.

process_error_content(_Element, false) ->
    false;
process_error_content(Element, _) ->
    verify_error_child_element(Element#xmlElement.name,
                               Element#xmlElement.content).

verify_error_child_element('Code', [Content]) ->
    Content#xmlText.value =:= "NoSuchBucket";
verify_error_child_element('Message', [Content]) ->
    Content#xmlText.value =:= "The specified bucket does not exist.";
verify_error_child_element('Resource', [Content]) ->
    Content#xmlText.value =:= "/riak_test_bucket";
verify_error_child_element(_, _) ->
    true.