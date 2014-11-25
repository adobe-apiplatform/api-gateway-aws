--
-- Created by IntelliJ IDEA.
-- User: nramaswa
-- Date: 6/4/14
-- Time: 5:03 PM
-- To change this template use File | Settings | File Templates.
--

local cjson = require"cjson"
local http = require"api-gateway.aws.httpclient.http"
local url = require"api-gateway.aws.httpclient.url"

local DEFAULT_SECURITY_CREDENTIALS_HOST = "169.254.169.254"
local DEFAULT_SECURITY_CREDENTIALS_PORT = "80"
local DEFAULT_SECURITY_CREDENTIALS_URL = "/latest/meta-data/iam/security-credentials/"
local DEFAULT_TOKEN_EXPIRATION = 3600 -- in seconds

-- per nginx process cache to store IAM credentials
local cache = {
    AccessKeyId = nil,
    SecretAccessKey = nil,
    Token = nil,
    ExpireAt = nil,
    ExpireAtTimestamp = nil
}

local AWSIAMCredentials = {}

function AWSIAMCredentials:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if (o ~= nil) then
        self.iam_user = o.iam_user
        self.security_credentials_timeout = o.security_credentials_timeout or DEFAULT_TOKEN_EXPIRATION
        self.security_credentials_host = o.security_credentials_host or DEFAULT_SECURITY_CREDENTIALS_HOST
        self.security_credentials_port = o.security_credentials_port or DEFAULT_SECURITY_CREDENTIALS_PORT
        self.security_credentials_url = o.security_credentials_url or DEFAULT_SECURITY_CREDENTIALS_URL
    end
    return o
end

local function getTimestamp(dateString, convertToUTC)
    local pattern = "(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)Z"
    local xyear, xmonth, xday, xhour, xminute,
    xseconds, xoffset, xoffsethour, xoffsetmin = dateString:match(pattern)
    local convertedTimestamp = os.time({
        year = xyear,
        month = xmonth,
        day = xday,
        hour = xhour,
        min = xminute,
        sec = xseconds
    })
    if (convertToUTC == true) then
        local offset = os.time() - os.time(os.date("!*t"))
        convertedTimestamp = convertedTimestamp + offset
    end
    return convertedTimestamp
end


function AWSIAMCredentials:fetchSecurityCredentialsFromAWS()
    local iamURL = self.security_credentials_url .. self.iam_user .. "?DurationSeconds=" .. self.security_credentials_timeout

    local hc1 = http:new()

    local ok, code, headers, status, body = hc1:request{
        host = self.security_credentials_host,
        port = self.security_credentials_port,
        url = iamURL,
        method = "GET"
    }

    ngx.log(ngx.DEBUG, "IAM RESPONSE:" .. tostring(body))

    local aws_response = cjson.decode(body)

    if (aws_response["Code"] == "Success") then
        -- set the values and the expiry time
        cache.AccessKeyId = aws_response["AccessKeyId"]
        cache.SecretAccessKey = aws_response["SecretAccessKey"]
        local token = url:encodeUrl(aws_response["Token"])
        cache.Token = token
        cache.ExpireAt = aws_response["Expiration"]
        cache.ExpireAtTimestamp = getTimestamp(cache.ExpireAt)
    end

    return ok
end

function AWSIAMCredentials:updateSecurityCredentials()
    self:fetchSecurityCredentialsFromAWS()
end

function AWSIAMCredentials:getSecurityCredentials()
    -- http://wiki.nginx.org/HttpLuaModule#ngx.time
    local now_in_secs = ngx.time
    local expireAtTimestamp = cache.ExpireAtTimestamp or now_in_secs

    if (now_in_secs >= expireAtTimestamp - 3 or cache.Token == nil or cache.SecretAccessKey == nil or cache.AccessKeyId == nil) then
        self:updateSecurityCredentials()
    end

    return cache.AccessKeyId, cache.SecretAccessKey, cache.Token
end

return AWSIAMCredentials
