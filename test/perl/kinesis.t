#  Running this unit test:
# TEST_NGINX_AWS_SECRET=${AWS_SECRET_ACCESS_KEY} TEST_NGINX_AWS_CLIENT_ID=${AWS_ACCESS_KEY_ID} TEST_NGINX_AWS_TOKEN=${AWS_SECURITY_TOKEN} \
# PATH=/usr/local/sbin:$PATH TEST_NGINX_SERVROOT=`pwd`/target/servroot TEST_NGINX_PORT=1989 prove -I ./test/resources/test-nginx/lib -r ./test/perl/kinesis.t

# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 4)-1;

my $pwd = cwd();

# try to read the nameservers used by the system resolver:
my @nameservers;
if (open my $in, "/etc/resolv.conf") {
    while (<$in>) {
        if (/^\s*nameserver\s+(\d+(?:\.\d+){3})(?:\s+|$)/) {
            push @nameservers, $1;
            if (@nameservers > 10) {
                last;
            }
        }
    }
    close $in;
}

if (!@nameservers) {
    # default to Google's open DNS servers
    push @nameservers, "8.8.8.8", "8.8.4.4";
}


warn "Using nameservers: \n@nameservers\n";

our $HttpConfig = <<_EOC_;
    # lua_package_path "$pwd/scripts/?.lua;;";
    lua_package_path 'src/lua/?.lua;;';
    lua_package_cpath 'src/lua/?.so;;';
    init_by_lua '
        local v = require "jit.v"
        v.on("$Test::Nginx::Util::ErrLogFile")
        require "resty.core"
    ';
    resolver @nameservers;
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__


=== TEST 1: test GenerateDataKey with given Credentials
--- http_config eval: $::HttpConfig
--- config
        error_log ../kinesis_test1_error.log debug;

        location = /latest/meta-data/iam/security-credentials/ {
            return 200 'test-iam-user';
        }

        location = /latest/meta-data/iam/security-credentials/test-iam-user {
            set_by_lua $expiration '
                            local offset = os.time() - os.time(os.date("!*t"))
                            return os.date("%Y-%m-%dT%H:%M:%SZ", os.time() + math.abs(offset) + 20)
                        ';
            return 200 '{
                          "Code" : "Success",
                          "LastUpdated" : "2014-11-03T01:56:20Z",
                          "Type" : "AWS-HMAC",
                          "AccessKeyId" : "$TEST_NGINX_AWS_CLIENT_ID",
                          "SecretAccessKey" : "$TEST_NGINX_AWS_SECRET",
                          "Token" : "$TEST_NGINX_AWS_TOKEN",
                          "Expiration" : "$expiration"
                        }';
        }

        location /test {
            set $aws_access_key $TEST_NGINX_AWS_CLIENT_ID;
            set $aws_secret_key $TEST_NGINX_AWS_SECRET;
            set $aws_region us-east-1;
            set $aws_service kms;

            content_by_lua '
                local KinesisService = require "api-gateway.aws.kinesis.KinesisService"
                local cjson = require "cjson"

                local service = KinesisService:new({
                    security_credentials_host = "127.0.0.1",
                    security_credentials_port = $TEST_NGINX_PORT,
                    aws_region = ngx.var.aws_region,
                    aws_debug = true,              -- print warn level messages on the nginx logs
                    aws_conn_keepalive = 60000,    -- how long to keep the sockets used for AWS alive
                    aws_conn_pool = 100            -- the connection pool size for sockets used to connect to AWS
                })

                -- search for streams
                local DEFAULT_STREAM_NAME = "test-stream"
                local list  = service:listStreams("test")
                if ( table.getn(list.StreamNames) == 0 ) then
                    ngx.log(ngx.DEBUG, "No Kinesis Streams found. Creating one.")
                    local json_response, code, headers, status, body = service:createStream(DEFAULT_STREAM_NAME)
                    assert( code == 200, "CreateStream Action should have returned with 200, but it returned with:" .. tostring(code) .. ", response:" .. tostring(body) )
                    ngx.sleep(60) -- give AWS time to create a new stream
                    list  = service:listStreams("test")
                    assert(table.getn(list.StreamNames) > 0, "At least one stream should have been created")
                end

                -- use putRecord to put a single record into DEFAULT_STREAM_NAME
                local data = "testas"
                local partitionKey = "partition"
                local json_response, code, headers, status, body = service:putRecord(DEFAULT_STREAM_NAME, data, partitionKey)
                assert( code == 200, "PutRecord Action should have returned with 200, but it returned with:" .. tostring(code) .. ", response:" .. tostring(body) )

                -- use putRecords to put a batch of records
                local records = {
                    {
                        Data = "55555",
                        PartitionKey = "partitionKey1"
                    },
                    {
                        Data = "7777777",
                        PartitionKey = "partitionKey2"
                    }
                }
                local json_response, code, headers, status, body = service:putRecords(DEFAULT_STREAM_NAME, records)
                assert( code == 200, "PutRecords Action should have returned with 200, but it returned with:" .. tostring(code) .. ", response:" .. tostring(body) )
                assert(json_response.FailedRecordCount == 0, "There are failed records during put")

                -- pick the first stream
                local streamName = list.StreamNames[1]
                ngx.say("STREAM-NAME:" .. tostring(streamName))

                if streamName == DEFAULT_STREAM_NAME then
                    -- delete the stream that was created by the test
                    local json_response, code, headers, status, body = service:deleteStream(DEFAULT_STREAM_NAME)
                    assert( code == 200, "DeleteStream Action should have returned with 200, but it returned with:" .. tostring(code) .. ", response:" .. tostring(body) )
                end

            ';
        }
--- timeout: 70
--- request
GET /test
--- response_body_like eval
[".*STREAM-NAME\\:.*"]
--- error_code: 200
--- no_error_log
[error]
--- more_headers
X-Test: test