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
        self.loggerSharedDict = ngx.shared[o.sharedDict]
    end
    return o
end


function AWSIAMCredentials:fetchSecurityCredentialsFromAWS()
    local iamURL = self.security_credentials_url .. self.iam_user .. "?DurationSeconds=" .. self.security_credentials_timeout

    -- expire the keys in the shared dict 6 seconds before the aws keys expire
    local expire_at = self.security_credentials_timeout - 6
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
        local loggerDict = self.loggerSharedDict
        -- set the values and the expiry time
        loggerDict:set("AccessKeyId", aws_response["AccessKeyId"], expire_at)
        loggerDict:set("SecretAccessKey", aws_response["SecretAccessKey"], expire_at)
        local token = url:encodeUrl(aws_response["Token"])
        loggerDict:set("Token", token, expire_at)
    end

    return ok
end

function AWSIAMCredentials:updateSecurityCredentials()
    self:fetchSecurityCredentialsFromAWS()
end

function AWSIAMCredentials:getSecurityCredentials()
    local accessKeyId = self.loggerSharedDict:get("AccessKeyId")

    if (accessKeyId == nil) then
        self:updateSecurityCredentials()
    end

    local accessKeyId = self.loggerSharedDict:get("AccessKeyId")
    local secretAccessKey = self.loggerSharedDict:get("SecretAccessKey")
    local token = self.loggerSharedDict:get("Token")

    return accessKeyId, secretAccessKey, token
end

return AWSIAMCredentials
