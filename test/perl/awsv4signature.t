# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 4) - 1;

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

    client_body_temp_path /tmp/;
    proxy_temp_path /tmp/;
    fastcgi_temp_path /tmp/;
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: test request args with same first character
--- http_config eval: $::HttpConfig
--- config
        location /test-signature {

            content_by_lua '
                local AWSV4S = require "api-gateway.aws.AwsV4Signature"
                local awsAuth =  AWSV4S:new()
                ngx.print(awsAuth:formatQueryString(ngx.req.get_uri_args()))
            ';
        }

--- more_headers
X-Test: test
--- request
POST /test-signature?Subject=nginx:test!@$&TopicArn=arn:aws:sns:us-east-1:492299007544:apiplatform-dev-ue1-topic-analytics&Message=hello_from_nginx,with_comma!&Action=Publish&Subject1=nginx:test
--- response_body eval
["Action=Publish&Message=hello_from_nginx%2Cwith_comma%21&Subject=nginx%3Atest%21%40%24&Subject1=nginx%3Atest&TopicArn=arn%3Aaws%3Asns%3Aus-east-1%3A492299007544%3Aapiplatform-dev-ue1-topic-analytics"]
--- no_error_log
[error]
--- error_code: 200
