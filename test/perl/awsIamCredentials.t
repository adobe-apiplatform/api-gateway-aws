# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use strict;
use warnings;
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 4)-3;

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
    lua_package_path 'src/lua/?.lua;/usr/local/lib/lua/?.lua;;';
    # lua_package_cpath 'src/lua/?.so;;';
    init_by_lua '
        local v = require "jit.v"
        v.on("$Test::Nginx::Util::ErrLogFile")
        require "resty.core"
    ';
    lua_shared_dict shared_cache 1m;
    resolver @nameservers;

    client_body_temp_path /tmp/;
    proxy_temp_path /tmp/;
    fastcgi_temp_path /tmp/;
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__


=== TEST 1: test auto discovery of iam user
--- http_config eval: $::HttpConfig
--- config
        error_log ../awsIamCredentials_test1_error.log debug;

        location = /latest/meta-data/iam/security-credentials/ {
            return 200 'test-iam-user';
        }

        location /test {
            content_by_lua '
                local IamCredentials = require "api-gateway.aws.AWSIAMCredentials"
                local iam = IamCredentials:new({
                    security_credentials_host = "127.0.0.1",
                    security_credentials_port = $TEST_NGINX_PORT
                })
                local iam_user, isCached = iam:getIamUser()
                ngx.say("User=" .. iam_user .. ", cached=" .. tostring(isCached) )

                iam_user, isCached = iam:getIamUser()
                ngx.say("User=" .. iam_user .. ", cached=" .. tostring(isCached) )
            ';
        }
--- request
GET /test
--- response_body_like eval
["User=test-iam-user, cached=false\nUser=test-iam-user, cached=true"]
--- error_code: 200
--- no_error_log
[error]
--- more_headers
X-Test: test

=== TEST 2: test Iam can automatically read credentials
--- http_config eval: $::HttpConfig
--- config
        error_log ../awsIamCredentials_test2_error.log debug;

        location = /latest/meta-data/iam/security-credentials/ {
            return 200 'test-iam-user';
        }

        location = /latest/meta-data/iam/security-credentials/test-iam-user {
            return 200 '{
                          "Code" : "Success",
                          "LastUpdated" : "2014-11-03T01:56:20Z",
                          "Type" : "AWS-HMAC",
                          "AccessKeyId" : "KEY",
                          "SecretAccessKey" : "SECRET",
                          "Token" : "TOKEN",
                          "Expiration" : "2014-11-03T08:07:52Z"
                        }';
        }

        location = /latest/meta-data/iam/security-credentials/newer-iam-user {
            set_by_lua $expiration '
                    local offset = os.time() - os.time(os.date("!*t"))
                    return os.date("%Y-%m-%dT%H:%M:%SZ", os.time() + math.abs(offset) + 10)
                ';
            return 200 '{
                          "Code" : "Success",
                          "LastUpdated" : "2014-11-03T01:56:20Z",
                          "Type" : "AWS-HMAC",
                          "AccessKeyId" : "KEY",
                          "SecretAccessKey" : "SECRET",
                          "Token" : "TOKEN",
                          "Expiration" : "$expiration"
                        }';
        }

        location /test {
            content_by_lua '
                local IamCredentials = require "api-gateway.aws.AWSIAMCredentials"
                local iam = IamCredentials:new({
                    security_credentials_host = "127.0.0.1",
                    security_credentials_port = $TEST_NGINX_PORT
                })

                local key,secret,token,date,timestamp = iam:getSecurityCredentials()
                ngx.say("key=" .. key .. ", secret=" .. secret .. ", token=" .. token .. ", date=" .. date .. ", timestamp=" ..timestamp )

                -- the previous token should be expired and a new call to fetch credentials should get a new token
                -- changing the iam_user will cause the IamCredentials to use this one when fetching new credentials
                iam.iam_user = "newer-iam-user"
                local offset = os.time() - os.time(os.date("!*t"))
                local d = os.date("%Y-%m-%dT%H:%M:%SZ", os.time() + math.abs(offset) + 10)

                local key,secret,token,date,timestamp = iam:getSecurityCredentials()

                local str1 = "key=" .. key .. ", secret=" .. secret .. ", token=" .. token .. ", date=" .. d .. ", timestamp=" .. timestamp
                ngx.say(str1)
                if ( date ~= d ) then
                    error("Dates should match. Got" .. date .. ", Expected: " .. d)
                end

                ngx.sleep(3)

                -- because the dates are in the future it should return the same date now
                local key,secret,token,date,timestamp = iam:getSecurityCredentials()
                local str2 = "key=" .. key .. ", secret=" .. secret .. ", token=" .. token .. ", date=" .. date .. ", timestamp=" .. timestamp
                if ( str1 ~= str2 ) then
                    error("Iam should have returned the same value. Got:" .. str2 .. ",Expected:" .. str1)
                end
            ';
        }
--- timeout: 20s
--- more_headers
X-Test: test
--- request
GET /test
--- response_body_like eval
["key=KEY, secret=SECRET, token=TOKEN, date=2014-11-03T08:07:52Z, timestamp=1415002072
key=KEY, secret=SECRET, token=TOKEN, date=\\d+-\\d+-\\d+T\\d+:\\d+:\\d+Z, timestamp=\\d+"]
--- error_code: 200
--- no_error_log
[error]
--- more_headers
X-Test: test


=== TEST 3: test Iam can automatically read credentials with SHARED DICT
--- http_config eval: $::HttpConfig
--- config
        error_log ../awsIamCredentials_test3_error.log debug;

        location = /latest/meta-data/iam/security-credentials/ {
            return 200 'test-iam-user';
        }

        location = /latest/meta-data/iam/security-credentials/test-iam-user {
            return 200 '{
                          "Code" : "Success",
                          "LastUpdated" : "2014-11-03T01:56:20Z",
                          "Type" : "AWS-HMAC",
                          "AccessKeyId" : "KEY",
                          "SecretAccessKey" : "SECRET",
                          "Token" : "TOKEN",
                          "Expiration" : "2014-11-03T08:07:52Z"
                        }';
        }

        location = /latest/meta-data/iam/security-credentials/newer-iam-user {
            set_by_lua $expiration '
                    local offset = os.time() - os.time(os.date("!*t"))
                    return os.date("%Y-%m-%dT%H:%M:%SZ", os.time() + math.abs(offset) + 10)
                ';
            return 200 '{
                          "Code" : "Success",
                          "LastUpdated" : "2014-11-03T01:56:20Z",
                          "Type" : "AWS-HMAC",
                          "AccessKeyId" : "KEY",
                          "SecretAccessKey" : "SECRET",
                          "Token" : "TOKEN",
                          "Expiration" : "$expiration"
                        }';
        }

        location /test {
            content_by_lua '
                local cjson = require "cjson"
                local IamCredentials = require "api-gateway.aws.AWSIAMCredentials"
                local iam = IamCredentials:new({
                    security_credentials_host = "127.0.0.1",
                    security_credentials_port = $TEST_NGINX_PORT,
                    shared_cache_dict = "shared_cache"
                })

                local key,secret,token,date,timestamp = iam:getSecurityCredentials()
                ngx.say("key=" .. key .. ", secret=" .. secret .. ", token=" .. token .. ", date=" .. date .. ", timestamp=" ..timestamp )

                local shared_cache = ngx.shared["shared_cache"]
                assert( shared_cache:get("iam_credentials") == nil, "iam_credentials should not be saved in shared cache, but found:" .. tostring(shared_cache:get("iam_credentials")))

                -- the previous token should be expired and a new call to fetch credentials should get a new token
                -- changing the iam_user will cause the IamCredentials to use this one when fetching new credentials
                iam.iam_user = "newer-iam-user"
                local offset = os.time() - os.time(os.date("!*t"))
                local d = os.date("%Y-%m-%dT%H:%M:%SZ", os.time() + math.abs(offset) + 10)

                local key,secret,token,date,timestamp = iam:getSecurityCredentials()

                local str1 = "key=" .. key .. ", secret=" .. secret .. ", token=" .. token .. ", date=" .. d .. ", timestamp=" .. timestamp
                ngx.say(str1)
                if ( date ~= d ) then
                    error("Dates should match. Got" .. date .. ", Expected: " .. d)
                end
                local cachedIam = shared_cache:get("iam_credentials")
                cachedIam = cjson.decode(cachedIam)
                assert( cachedIam ~= nil, "iam_credentials should be saved in shared cache")
                assert( cachedIam.AccessKeyId ~= nil, "AccessKeyId should be saved in shared cache")
                assert( cachedIam.SecretAccessKey ~= nil, "SecretAccessKey should be saved in shared cache")
                assert( cachedIam.Token ~= nil, "Token should be saved in shared cache")
                assert( cachedIam.ExpireAt ~= nil, "ExpireAt should be saved in shared cache")
                assert( cachedIam.ExpireAtTimestamp ~= nil, "ExpireAtTimestamp should be saved in shared cache")

                ngx.sleep(3)

                -- because the dates are in the future it should return the same date now
                local key,secret,token,date,timestamp = iam:getSecurityCredentials()
                local str2 = "key=" .. key .. ", secret=" .. secret .. ", token=" .. token .. ", date=" .. date .. ", timestamp=" .. timestamp
                if ( str1 ~= str2 ) then
                    error("Iam should have returned the same value. Got:" .. str2 .. ",Expected:" .. str1)
                end
            ';
        }
--- timeout: 20s
--- request
GET /test
--- response_body_like eval
["key=KEY, secret=SECRET, token=TOKEN, date=2014-11-03T08:07:52Z, timestamp=1415002072
key=KEY, secret=SECRET, token=TOKEN, date=\\d+-\\d+-\\d+T\\d+:\\d+:\\d+Z, timestamp=\\d+"]
--- error_code: 200
--- no_error_log
[error]
--- more_headers
X-Test: test



